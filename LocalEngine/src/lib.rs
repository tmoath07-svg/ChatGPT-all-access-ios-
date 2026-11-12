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
        match &entry.kind {
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


fn resource_mapping(extension: &str) -> Result<(&'static str, bool), String> {
    match extension.to_ascii_lowercase().as_str() {
        "yft" => Ok(("oft", true)),
        "ydr" => Ok(("odr", true)),
        "ydd" => Ok(("odd", true)),
        "ypt" => Ok(("opt", true)),
        "ybn" => Ok(("obn", true)),
        "ybd" => Ok(("obd", true)),
        "yld" => Ok(("old", true)),
        "yed" => Ok(("oed", true)),
        "yfd" => Ok(("ofd", true)),
        "ynd" => Ok(("ond", true)),
        "ynv" => Ok(("onv", true)),
        "yvr" => Ok(("ovr", true)),
        "ywr" => Ok(("owr", true)),
        "ypdb" => Ok(("opdb", true)),
        "ycd" => Ok(("ocd", false)),
        "ymap" => Ok(("omap", false)),
        "ytyp" => Ok(("otyp", false)),
        "ymt" => Ok(("omt", false)),
        "ymf" => Ok(("omf", false)),
        "ytd" => Err("ملف YTD يحتاج محرك بناء OTD الخاص بالخامات، وهذا الجزء لم يُنقل بعد.".to_string()),
        _ => Err(format!("امتداد المورد غير مدعوم للتحويل المحلي: .{extension}")),
    }
}

fn read_decompressed_payload(payload: &[u8]) -> Result<Vec<u8>, String> {
    use flate2::read::{DeflateDecoder, GzDecoder, ZlibDecoder};
    use std::io::Read;

    let mut raw = Vec::new();
    if DeflateDecoder::new(payload).read_to_end(&mut raw).is_ok() && !raw.is_empty() {
        return Ok(raw);
    }
    raw.clear();
    if ZlibDecoder::new(payload).read_to_end(&mut raw).is_ok() && !raw.is_empty() {
        return Ok(raw);
    }
    raw.clear();
    if GzDecoder::new(payload).read_to_end(&mut raw).is_ok() && !raw.is_empty() {
        return Ok(raw);
    }
    Err("تعذر فك ضغط RSC7 باستخدام صيغ DEFLATE المعروفة. لم يتم تعديل الملف.".to_string())
}

fn replace_marker(data: &mut [u8]) -> usize {
    const PC_MARKER: [u8; 8] = [0x96, 0x69, 0x99, 0x55, 0x55, 0x55, 0x55, 0x77];
    const PS4_MARKER: [u8; 8] = [0x96, 0x68, 0x99, 0x55, 0x55, 0x55, 0x55, 0x77];
    if data.len() < PC_MARKER.len() {
        return 0;
    }
    let mut count = 0usize;
    let mut index = 0usize;
    while index + PC_MARKER.len() <= data.len() {
        if data[index..index + PC_MARKER.len()] == PC_MARKER {
            data[index..index + PS4_MARKER.len()].copy_from_slice(&PS4_MARKER);
            count += 1;
            index += PC_MARKER.len();
        } else {
            index += 1;
        }
    }
    count
}

fn convert_resource_bytes(extension: &str, input: &[u8]) -> Result<(String, Vec<u8>, usize, String), String> {
    use flate2::write::DeflateEncoder;
    use flate2::Compression;
    use std::io::Write;

    let (output_extension, needs_patch) = resource_mapping(extension)?;
    if !needs_patch {
        return Ok((output_extension.to_string(), input.to_vec(), 0, "extension-only".to_string()));
    }
    if input.len() < 16 {
        return Err("ملف المورد أقصر من ترويسة RSC7.".to_string());
    }
    if &input[0..4] != b"RSC7" {
        return Ok((output_extension.to_string(), input.to_vec(), 0, "extension-only-no-RSC7".to_string()));
    }

    let mut payload = read_decompressed_payload(&input[16..])?;
    let patched = replace_marker(&mut payload);
    let mut encoder = DeflateEncoder::new(Vec::new(), Compression::new(6));
    encoder.write_all(&payload).map_err(|error| format!("فشل ضغط مورد PS4: {error}"))?;
    let compressed = encoder.finish().map_err(|error| format!("فشل إنهاء ضغط مورد PS4: {error}"))?;

    let mut output = Vec::with_capacity(16 + compressed.len());
    output.extend_from_slice(&input[..16]);
    output.extend_from_slice(&compressed);
    if output.len() <= 16 {
        return Err("الناتج غير صالح: لا يوجد محتوى بعد ترويسة RSC7.".to_string());
    }
    Ok((output_extension.to_string(), output, patched, "rsc7-structural-patch".to_string()))
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_convert_resource(
    input_path: *const c_char,
    output_directory: *const c_char,
) -> *mut c_char {
    let input = match read_c_path(input_path) {
        Ok(value) => PathBuf::from(value),
        Err(error) => return result_error(error),
    };
    let output_dir = match read_c_path(output_directory) {
        Ok(value) => PathBuf::from(value),
        Err(error) => return result_error(error),
    };
    if !input.is_file() {
        return result_error("ملف المورد المحدد غير موجود.");
    }
    let extension = match input.extension().and_then(|v| v.to_str()) {
        Some(value) => value,
        None => return result_error("ملف المورد لا يحتوي امتداداً معروفاً."),
    };
    let source = match fs::read(&input) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذرت قراءة المورد: {error}")),
    };
    if source.len() as u64 > MAX_INPUT_BYTES {
        return result_error("حجم المورد تجاوز حد المعالجة المحلي (1GB).");
    }
    let (new_extension, converted, patched, mode) = match convert_resource_bytes(extension, &source) {
        Ok(value) => value,
        Err(error) => return result_error(error),
    };
    if let Err(error) = fs::create_dir_all(&output_dir) {
        return result_error(format!("تعذر إنشاء مجلد المخرجات: {error}"));
    }
    let stem = input.file_stem().and_then(|v| v.to_str()).unwrap_or("resource");
    let output = output_dir.join(format!("{stem}.{new_extension}"));
    let temp = output.with_extension(format!("{new_extension}.tmp"));
    let write_result = (|| -> Result<(), String> {
        let mut file = fs::File::create(&temp).map_err(|error| format!("تعذر إنشاء ملف مؤقت: {error}"))?;
        file.write_all(&converted).map_err(|error| format!("تعذرت كتابة المورد المحوّل: {error}"))?;
        file.sync_all().map_err(|error| format!("تعذر حفظ المورد المحوّل: {error}"))?;
        fs::rename(&temp, &output).map_err(|error| format!("تعذر اعتماد الناتج: {error}"))?;
        Ok(())
    })();
    if let Err(error) = write_result {
        let _ = fs::remove_file(&temp);
        return result_error(error);
    }
    result_ok(json!({
        "ok": true,
        "input_extension": format!(".{extension}"),
        "output_extension": format!(".{new_extension}"),
        "mode": mode,
        "patched_markers": patched,
        "input_bytes": source.len(),
        "output_bytes": converted.len(),
        "output": output.to_string_lossy(),
        "warning": "هذه مرحلة تحويل بنيوي RSC7 فقط. ملفات YTD تحتاج محرك OTD، وبناء RPF/PS4 DLC واختبار اللعبة مراحل منفصلة."
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use rpf_archive::{RpfArchive, RpfBuilder, RpfEncryption};

    #[test]
    fn builds_parses_and_extracts_open_rpf7() {
        let expected = b"<CVehicleModelInfo__InitDataList/>";
        let mut builder = RpfBuilder::new(RpfEncryption::Open);
        builder.add_file("common/data/vehicles.meta", expected.to_vec());
        builder.add_file("x64/levels/gta5/vehicles/demo.yft", b"YFT_TEST_BYTES".to_vec());
        let bytes = builder.build(None).expect("build RPF7");
        let parsed = RpfArchive::parse(&bytes, "test.rpf", None).expect("parse RPF7");
        assert!(parsed.entries.len() >= 3);
        assert_eq!(parsed.encryption, RpfEncryption::Open);
        let meta = parsed.entries.iter().find(|entry| entry.name_lower == "vehicles.meta").expect("metadata entry");
        let extracted = parsed.extract_entry(&bytes, meta, None).expect("extract metadata");
        assert_eq!(extracted, expected);
    }

    #[test]
    fn patches_rsc7_structural_marker_and_preserves_header() {
        use flate2::write::DeflateEncoder;
        use flate2::Compression;
        use std::io::Write;

        let pc = [0x96, 0x69, 0x99, 0x55, 0x55, 0x55, 0x55, 0x77];
        let ps4 = [0x96, 0x68, 0x99, 0x55, 0x55, 0x55, 0x55, 0x77];
        let mut payload = b"test-model:".to_vec();
        payload.extend_from_slice(&pc);
        payload.extend_from_slice(b":end");
        let mut encoder = DeflateEncoder::new(Vec::new(), Compression::new(6));
        encoder.write_all(&payload).unwrap();
        let compressed = encoder.finish().unwrap();
        let mut input = b"RSC7".to_vec();
        input.extend_from_slice(&[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        input.extend_from_slice(&compressed);

        let (extension, output, count, mode) = convert_resource_bytes("yft", &input).unwrap();
        assert_eq!(extension, "oft");
        assert_eq!(count, 1);
        assert_eq!(mode, "rsc7-structural-patch");
        assert_eq!(&output[..16], &input[..16]);
        let decoded = read_decompressed_payload(&output[16..]).unwrap();
        assert!(decoded.windows(8).any(|window| window == ps4));
        assert!(!decoded.windows(8).any(|window| window == pc));
    }

    #[test]
    fn refuses_ytd_until_native_otd_builder_exists() {
        let error = convert_resource_bytes("ytd", b"not a ytd").unwrap_err();
        assert!(error.contains("OTD"));
    }
}
