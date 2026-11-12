use rpf_archive::{RpfArchive, RpfBuilder, RpfEncryption, RpfEntryKind};
use serde_json::json;
use std::ffi::{CStr, CString};
use std::fs;
use std::io::Write;
use std::os::raw::c_char;
use std::path::{Component, Path, PathBuf};

const MAX_INPUT_BYTES: u64 = 1024 * 1024 * 1024;
const MAX_FILES: usize = 20_000;
const MAX_DEPTH: usize = 64;

fn c_string(value: String) -> *mut c_char {
    CString::new(value.replace('\0', "�"))
        .unwrap_or_else(|_| CString::new("{\"ok\":false,\"error\":\"invalid response\"}").unwrap())
        .into_raw()
}

unsafe fn read_c_path<'a>(value: *const c_char) -> Result<&'a str, String> {
    if value.is_null() {
        return Err("مسار الملف غير موجود.".to_string());
    }
    CStr::from_ptr(value)
        .to_str()
        .map_err(|_| "المسار يحتوي أحرفاً غير صالحة.".to_string())
}

fn result_ok(value: serde_json::Value) -> *mut c_char {
    c_string(value.to_string())
}

fn result_error(message: impl Into<String>) -> *mut c_char {
    result_ok(json!({ "ok": false, "error": message.into() }))
}

#[no_mangle]
pub extern "C" fn gta_engine_version() -> *const c_char {
    b"GTA Local Engine 0.1.0\0".as_ptr() as *const c_char
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_free_string(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_probe_rpf(path: *const c_char) -> *mut c_char {
    let path = match read_c_path(path) {
        Ok(value) => Path::new(value),
        Err(error) => return result_error(error),
    };

    let metadata = match fs::metadata(path) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذر قراءة الملف: {error}")),
    };
    if metadata.len() > MAX_INPUT_BYTES {
        return result_error("حجم RPF أكبر من حد الفحص المحلي (1GB).");
    }

    let bytes = match fs::read(path) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذرت قراءة بيانات RPF: {error}")),
    };
    let name = path.file_name().and_then(|v| v.to_str()).unwrap_or("archive.rpf");
    let archive = match RpfArchive::parse(&bytes, name, None) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذر تحليل RPF: {error:#}")),
    };

    let mut directories = 0usize;
    let mut binary_files = 0usize;
    let mut resource_files = 0usize;
    for entry in &archive.entries {
        match entry.kind {
            RpfEntryKind::Directory { .. } => directories += 1,
            RpfEntryKind::BinaryFile { .. } => binary_files += 1,
            RpfEntryKind::ResourceFile { .. } => resource_files += 1,
        }
    }

    let version = match archive.version {
        rpf_archive::RpfVersion::V7 => "RPF7",
        rpf_archive::RpfVersion::V8 => "RPF8",
        rpf_archive::RpfVersion::V6 => "RPF6",
        rpf_archive::RpfVersion::V4 => "RPF4",
        rpf_archive::RpfVersion::V3 => "RPF3",
        rpf_archive::RpfVersion::V2 => "RPF2",
        rpf_archive::RpfVersion::V0 => "RPF0",
        rpf_archive::RpfVersion::Img1 => "IMG1",
        rpf_archive::RpfVersion::Img2 => "IMG2",
        rpf_archive::RpfVersion::Img3 => "IMG3",
    };

    result_ok(json!({
        "ok": true,
        "format": version,
        "encryption": format!("{:?}", archive.encryption),
        "bytes": metadata.len(),
        "entries": archive.entries.len(),
        "directories": directories,
        "binary_files": binary_files,
        "resource_files": resource_files,
        "warning": "الفحص البنيوي لا يثبت توافق موارد اللعبة مع PS4."
    }))
}

fn collect_files(
    root: &Path,
    current: &Path,
    depth: usize,
    files: &mut Vec<(String, PathBuf, u64)>,
    total_bytes: &mut u64,
) -> Result<(), String> {
    if depth > MAX_DEPTH {
        return Err(format!("تجاوز عمق المجلدات الحد المسموح ({MAX_DEPTH})."));
    }
    let entries = fs::read_dir(current)
        .map_err(|error| format!("تعذر فتح المجلد {}: {error}", current.display()))?;

    for item in entries {
        let item = item.map_err(|error| format!("تعذر قراءة أحد عناصر المجلد: {error}"))?;
        let path = item.path();
        let metadata = fs::symlink_metadata(&path)
            .map_err(|error| format!("تعذر قراءة بيانات {}: {error}", path.display()))?;

        // Symlinks are intentionally skipped to prevent loops and escaping the selected folder.
        if metadata.file_type().is_symlink() {
            continue;
        }
        if metadata.is_dir() {
            collect_files(root, &path, depth + 1, files, total_bytes)?;
            continue;
        }
        if !metadata.is_file() {
            continue;
        }

        let relative = path.strip_prefix(root)
            .map_err(|_| "مسار ملف خرج عن مجلد المصدر.".to_string())?;
        let mut safe_parts = Vec::new();
        for component in relative.components() {
            match component {
                Component::Normal(part) => {
                    let text = part.to_str().ok_or_else(|| "اسم ملف غير مدعوم بترميز UTF-8.".to_string())?;
                    if text.is_empty() || text == "." || text == ".." {
                        return Err("تم رفض مسار ملف غير آمن.".to_string());
                    }
                    safe_parts.push(text.to_string());
                }
                _ => return Err("تم رفض مسار ملف غير آمن.".to_string()),
            }
        }
        if safe_parts.is_empty() {
            continue;
        }
        let archive_path = safe_parts.join("/");
        let size = metadata.len();
        *total_bytes = total_bytes.saturating_add(size);
        if *total_bytes > MAX_INPUT_BYTES {
            return Err("مجموع الملفات تجاوز حد المعالجة المحلي (1GB).".to_string());
        }
        files.push((archive_path, path, size));
        if files.len() > MAX_FILES {
            return Err(format!("عدد الملفات تجاوز الحد المسموح ({MAX_FILES})."));
        }
    }
    Ok(())
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_build_rpf7(
    input_directory: *const c_char,
    output_file: *const c_char,
) -> *mut c_char {
    let input = match read_c_path(input_directory) {
        Ok(value) => PathBuf::from(value),
        Err(error) => return result_error(error),
    };
    let output = match read_c_path(output_file) {
        Ok(value) => PathBuf::from(value),
        Err(error) => return result_error(error),
    };

    if !input.is_dir() {
        return result_error("المصدر المحدد ليس مجلداً.");
    }
    if output.starts_with(&input) {
        return result_error("يجب حفظ ملف RPF خارج مجلد المصدر.");
    }

    let mut files = Vec::new();
    let mut total_bytes = 0u64;
    if let Err(error) = collect_files(&input, &input, 0, &mut files, &mut total_bytes) {
        return result_error(error);
    }
    if files.is_empty() {
        return result_error("المجلد فارغ، لا توجد ملفات لبناء RPF.");
    }

    let mut builder = RpfBuilder::new(RpfEncryption::Open);
    for (archive_path, source_path, _) in &files {
        let data = match fs::read(source_path) {
            Ok(value) => value,
            Err(error) => return result_error(format!("تعذرت قراءة {}: {error}", source_path.display())),
        };
        builder.add_file(archive_path, data);
    }

    let archive_bytes = match builder.build(None) {
        Ok(value) => value,
        Err(error) => return result_error(format!("فشل بناء RPF7: {error:#}")),
    };

    let parsed = match RpfArchive::parse(&archive_bytes, "local-build.rpf", None) {
        Ok(value) => value,
        Err(error) => return result_error(format!("فشل فحص RPF الناتج: {error:#}")),
    };
    if parsed.entries.len() < files.len() {
        return result_error("فشل التحقق: عدد مدخلات RPF الناتج أقل من عدد الملفات المصدرية.");
    }

    if let Some(parent) = output.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return result_error(format!("تعذر إنشاء مجلد الناتج: {error}"));
        }
    }
    let temp = output.with_extension("rpf.tmp");
    let write_result = (|| -> Result<(), String> {
        let mut file = fs::File::create(&temp)
            .map_err(|error| format!("تعذر إنشاء ملف مؤقت: {error}"))?;
        file.write_all(&archive_bytes)
            .map_err(|error| format!("تعذرت كتابة RPF: {error}"))?;
        file.sync_all().map_err(|error| format!("تعذر حفظ RPF: {error}"))?;
        fs::rename(&temp, &output)
            .map_err(|error| format!("تعذر اعتماد ملف RPF النهائي: {error}"))?;
        Ok(())
    })();
    if let Err(error) = write_result {
        let _ = fs::remove_file(&temp);
        return result_error(error);
    }

    result_ok(json!({
        "ok": true,
        "format": "RPF7",
        "encryption": "Open",
        "files": files.len(),
        "input_bytes": total_bytes,
        "output_bytes": archive_bytes.len(),
        "output": output.to_string_lossy(),
        "validated_entries": parsed.entries.len(),
        "warning": "تم بناء أرشيف RPF7 وفحص بنيته فقط. لم تتم معالجة RSC7 أو تحويل موارد PS4، لذلك لا تعتبره DLC متوافقاً مع PS4."
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use rpf_archive::{RpfArchive, RpfBuilder, RpfEncryption};

    #[test]
    fn builds_and_parses_open_rpf7() {
        let mut builder = RpfBuilder::new(RpfEncryption::Open);
        builder.add_file("common/data/vehicles.meta", b"<CVehicleModelInfo__InitDataList/>".to_vec());
        builder.add_file("x64/levels/gta5/vehicles/demo.yft", b"YFT_TEST_BYTES".to_vec());
        let bytes = builder.build(None).expect("build RPF7");
        let parsed = RpfArchive::parse(&bytes, "test.rpf", None).expect("parse RPF7");
        assert!(parsed.entries.len() >= 3);
        assert_eq!(parsed.encryption, RpfEncryption::Open);
    }
}
