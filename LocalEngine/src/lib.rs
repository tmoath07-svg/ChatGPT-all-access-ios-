use rpf_archive::{RpfArchive, RpfBuilder, RpfEncryption, RpfEntryKind};
use serde_json::json;
use std::ffi::{CStr, CString};
use std::fs;
use std::io::Write;
use std::os::raw::c_char;
use std::path::{Component, Path, PathBuf};
use suppaftp::{types::FileType, FtpError, FtpStream, Mode};

const MAX_INPUT_BYTES: u64 = 512 * 1024 * 1024;
const MAX_RESOURCE_DECOMPRESSED_BYTES: u64 = 512 * 1024 * 1024;
const MAX_FILES: usize = 20_000;
const MAX_DEPTH: usize = 64;

const VEHICLE_METADATA_NAMES: [&str; 5] = [
    "vehicles.meta",
    "handling.meta",
    "carcols.meta",
    "carvariations.meta",
    "vehiclelayouts.meta",
];

fn is_vehicle_metadata_name(name: &str) -> bool {
    let basename = name.rsplit('/').next().unwrap_or(name).to_ascii_lowercase();
    VEHICLE_METADATA_NAMES.contains(&basename.as_str())
}

fn archive_has_vehicle_metadata(archive: &RpfArchive) -> bool {
    archive.entries.iter().any(|entry| is_vehicle_metadata_name(&entry.name_lower))
}

fn contains_vehicle_metadata(root: &Path, max_depth: usize) -> bool {
    if !root.is_dir() { return false; }
    let mut pending = vec![(root.to_path_buf(), 0usize)];
    let mut visited = 0usize;
    while let Some((directory, depth)) = pending.pop() {
        let Ok(entries) = fs::read_dir(&directory) else { continue };
        for item in entries.flatten() {
            visited += 1;
            if visited > MAX_FILES * 2 { return false; }
            let Ok(kind) = item.file_type() else { continue };
            if kind.is_symlink() { continue; }
            let name = item.file_name().to_string_lossy().to_ascii_lowercase();
            if kind.is_file() && VEHICLE_METADATA_NAMES.contains(&name.as_str()) {
                return true;
            }
            if kind.is_dir() && depth < max_depth {
                pending.push((item.path(), depth + 1));
            }
        }
    }
    false
}

fn has_fivem_manifest(root: &Path) -> bool {
    root.join("fxmanifest.lua").is_file() || root.join("__resource.lua").is_file()
}

fn has_vehicle_metadata_near(path: &Path) -> bool {
    let mut current = if path.is_dir() { Some(path) } else { path.parent() };
    for _ in 0..5 {
        let Some(directory) = current else { break };
        if contains_vehicle_metadata(directory, 4) { return true; }
        current = directory.parent();
    }
    false
}

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
        return result_error("حجم RPF أكبر من حد الفحص المحلي (512MB).");
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
    if let Err(error) = ensure_rpf_archive_names_readable(&archive) {
        return result_error(error);
    }
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
        "has_vehicle_metadata": archive_has_vehicle_metadata(&archive),
        "warning": "تم فحص بنية RPF بصرف النظر عن نوع محتواه. وجود بيانات مركبة لا يثبت توافق الموارد مع PS4."
    }))
}



const MAX_PREVIEW_MESHES: usize = 16;
const MAX_PREVIEW_VERTICES: usize = 40_000;
const MAX_PREVIEW_INDICES: usize = 120_000;

#[no_mangle]
pub unsafe extern "C" fn gta_engine_preview_vehicle_model(path: *const c_char) -> *mut c_char {
    let path = match read_c_path(path) {
        Ok(value) => Path::new(value),
        Err(error) => return result_error(error),
    };
    let metadata = match fs::metadata(path) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذر قراءة ملف المركبة: {error}")),
    };
    if !metadata.is_file() {
        return result_error("المصدر المحدد ليس ملفاً عادياً.");
    }
    if metadata.len() > MAX_INPUT_BYTES {
        return result_error("حجم ملف المركبة تجاوز حد التحليل المحلي (512MB).");
    }
    if !has_vehicle_metadata_near(path) {
        return result_error("اختر نموذجاً من مجلد يحتوي بيانات مركبة مدعومة.");
    }
    let extension = path.extension().and_then(|value| value.to_str()).unwrap_or("");
    let kind = match rage_formats::DrawableKind::from_extension(extension) {
        Some(value) => value,
        None => return result_error("عارض المركبات يدعم YFT وYDR وYDD فقط."),
    };
    let bytes = match fs::read(path) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذرت قراءة ملف المركبة: {error}")),
    };
    let entries = match rage_formats::parse_drawables(&bytes, kind) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذر تحليل نموذج المركبة: {error:#}")),
    };

    let mut meshes = Vec::new();
    let mut warnings = Vec::new();
    for entry in entries {
        let drawable = entry.drawable;
        let lod = drawable.lods.iter()
            .find(|value| value.level == rage_formats::LodLevel::High)
            .or_else(|| drawable.lods.first());
        let Some(lod) = lod else {
            warnings.push(format!("{}: لا توجد مستويات LOD قابلة للعرض.", entry.name));
            continue;
        };
        for (model_index, model) in lod.models.iter().enumerate() {
            for (geometry_index, geometry) in model.geometries.iter().enumerate() {
                if meshes.len() >= MAX_PREVIEW_MESHES {
                    warnings.push(format!("تم إيقاف العرض عند {MAX_PREVIEW_MESHES} أجزاء لتقليل استهلاك الذاكرة."));
                    break;
                }
                let Some(vertex_buffer) = geometry.vertex_buffer.as_ref() else { continue };
                let vertices = match vertex_buffer.to_unified_vertices() {
                    Ok(value) => value,
                    Err(error) => {
                        warnings.push(format!("تعذر فك رؤوس الهندسة {geometry_index}: {error}"));
                        continue;
                    }
                };
                if vertices.is_empty() || vertices.len() > MAX_PREVIEW_VERTICES {
                    warnings.push(format!("تم تجاوز هندسة كبيرة أو فارغة: {} vertices.", vertices.len()));
                    continue;
                }
                let Some(index_buffer) = geometry.index_buffer.as_ref() else { continue };
                let indices = &index_buffer.indices;
                if indices.len() < 3 || indices.len() > MAX_PREVIEW_INDICES || indices.len() % 3 != 0 {
                    warnings.push(format!("فهرس المثلثات غير صالح في الهندسة {geometry_index}."));
                    continue;
                }
                if indices.iter().any(|index| *index as usize >= vertices.len()) {
                    warnings.push(format!("تم تجاهل هندسة تحتوي مؤشرات خارج نطاق الرؤوس: {geometry_index}."));
                    continue;
                }
                let positions = vertices.iter()
                    .map(|vertex| [vertex.position.x, vertex.position.y, vertex.position.z])
                    .collect::<Vec<_>>();
                meshes.push(json!({
                    "name": entry.name,
                    "lod": lod.level.as_str(),
                    "model": model_index,
                    "geometry": geometry_index,
                    "vertices": positions,
                    "indices": indices,
                    "vertex_count": vertices.len(),
                    "triangle_count": indices.len() / 3
                }));
            }
            if meshes.len() >= MAX_PREVIEW_MESHES { break; }
        }
    }
    if meshes.is_empty() {
        return result_error("تم تحليل الملف لكن لم يتم العثور على هندسة مركبة قابلة للعرض ضمن الصيغ المدعومة.");
    }
    result_ok(json!({
        "ok": true,
        "format": extension.to_ascii_uppercase(),
        "meshes": meshes,
        "mesh_count": meshes.len(),
        "warning": format!(
            "معاينة هندسية للـLOD العالي أو أول LOD فقط. الخامات والعظام والتحريك غير معروضة. {}",
            warnings.join(" | ")
        )
    }))
}

fn resolve_rpf_root_range(entries: &[rpf_archive::RpfEntry]) -> Result<(u32, u32), String> {
    let root = entries.first().ok_or_else(|| "جدول RPF فارغ.".to_string())?;
    match &root.kind {
        RpfEntryKind::Directory { entries_index, entries_count } => {
            let start = *entries_index as usize;
            let end = start.checked_add(*entries_count as usize)
                .ok_or_else(|| "نطاق مجلد جذر RPF غير صالح.".to_string())?;
            if (start == 0 && *entries_count > 0) || end > entries.len() {
                return Err("نطاق مجلد جذر RPF خارج جدول الأرشيف أو يشير إلى نفسه.".to_string());
            }
            Ok((*entries_index, *entries_count))
        }
        _ if entries.iter().all(|entry| !matches!(&entry.kind, RpfEntryKind::Directory { .. })) => {
            let count = u32::try_from(entries.len())
                .map_err(|_| "عدد عناصر RPF يتجاوز الحد المدعوم.".to_string())?;
            Ok((0, count))
        }
        _ => Err("الأرشيف لا يحتوي على مجلد جذر، كما أن جدول الملفات يتضمن مجلدات داخلية؛ تم إيقاف الاستخراج لتجنب ترتيب ملفات خاطئ.".to_string()),
    }
}

fn ensure_rpf_archive_names_readable(archive: &RpfArchive) -> Result<(), String> {
    if archive.encryption.is_encrypted() {
        return Err(format!(
            "فهرس RPF مشفر ({:?}) ولا يمكن قراءة أسماء الملفات بدقة دون مفاتيح فك التشفير. أوقف AUTO قبل استخدام أسماء مشوهة.",
            archive.encryption
        ));
    }

    if let Some(entry) = archive.entries.iter().find(|entry| {
        entry.name.contains('\u{FFFD}')
            || entry.name.chars().any(|character| character.is_control())
    }) {
        let codepoints = entry.name.chars()
            .map(|character| format!("U+{:04X}", character as u32))
            .collect::<Vec<_>>()
            .join(" ");
        return Err(format!(
            "اسم RPF تالف أو ترميزه غير صالح: {:?} (Unicode: {}). لم يتم استخراج أو تركيب أي ملف.",
            entry.name, codepoints
        ));
    }
    Ok(())
}

fn validate_rpf_entry_name(name: &str) -> Result<(), String> {
    // A single RPF entry is one path component. Colons are valid filename
    // characters on the iOS target and do not create path traversal; separators,
    // dot segments, and control characters remain forbidden.
    let unsafe_name = name.is_empty()
        || name == "."
        || name == ".."
        || name.contains('/')
        || name.contains('\\')
        || name.chars().any(|character| character.is_control());
    if unsafe_name {
        let codepoints = name.chars()
            .map(|character| format!("U+{:04X}", character as u32))
            .collect::<Vec<_>>()
            .join(" ");
        return Err(format!(
            "اسم عنصر غير آمن داخل RPF: {:?} (Unicode: {})",
            name, codepoints
        ));
    }
    Ok(())
}

fn collect_rpf_listing(
    archive: &RpfArchive,
    start: u32,
    count: u32,
    prefix: &str,
    depth: usize,
    items: &mut Vec<serde_json::Value>,
) -> Result<(), String> {
    if depth > MAX_DEPTH {
        return Err(format!("تجاوز عمق شجرة RPF الحد المسموح ({MAX_DEPTH})."));
    }
    let begin = start as usize;
    let end = begin.checked_add(count as usize)
        .ok_or_else(|| "نطاق جدول RPF غير صالح أثناء بناء الشجرة.".to_string())?;
    if end > archive.entries.len() {
        return Err("مدخلات مجلد RPF تشير إلى نطاق خارج جدول الأرشيف.".to_string());
    }

    for entry in &archive.entries[begin..end] {
        let name = entry.name.as_str();
        validate_rpf_entry_name(name)?;
        let path = if prefix.is_empty() { name.to_string() } else { format!("{prefix}/{name}") };
        match &entry.kind {
            RpfEntryKind::Directory { entries_index, entries_count } => {
                if items.len() >= MAX_FILES {
                    return Err(format!("تجاوز عدد عناصر RPF الحد المسموح ({MAX_FILES})."));
                }
                items.push(json!({"path": path, "kind": "directory"}));
                collect_rpf_listing(
                    archive, *entries_index, *entries_count, &path, depth + 1, items,
                )?;
            }
            RpfEntryKind::BinaryFile { .. } => {
                if items.len() >= MAX_FILES {
                    return Err(format!("تجاوز عدد عناصر RPF الحد المسموح ({MAX_FILES})."));
                }
                let kind = if is_vehicle_metadata_name(name) { "vehicle_metadata" } else { "file" };
                items.push(json!({"path": path, "kind": kind}));
            }
            RpfEntryKind::ResourceFile { .. } => {
                if items.len() >= MAX_FILES {
                    return Err(format!("تجاوز عدد عناصر RPF الحد المسموح ({MAX_FILES})."));
                }
                let kind = if is_vehicle_metadata_name(name) { "vehicle_metadata" } else { "resource" };
                items.push(json!({"path": path, "kind": kind}));
            }
        }
    }
    Ok(())
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_list_rpf(path: *const c_char) -> *mut c_char {
    let path = match read_c_path(path) {
        Ok(value) => Path::new(value),
        Err(error) => return result_error(error),
    };
    let metadata = match fs::metadata(path) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذر قراءة الملف: {error}")),
    };
    if !metadata.is_file() {
        return result_error("المصدر المحدد ليس ملفاً.");
    }
    if metadata.len() > MAX_INPUT_BYTES {
        return result_error("حجم RPF أكبر من حد الفحص المحلي (512MB).");
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
    let (start, count) = match resolve_rpf_root_range(&archive.entries) {
        Ok(value) => value,
        Err(error) => return result_error(error),
    };
    let mut items = Vec::new();
    if let Err(error) = collect_rpf_listing(&archive, start, count, "", 0, &mut items) {
        return result_error(error);
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
        "count": items.len(),
        "items": items,
        "warning": "يعرض مستعرض RPF شجرة الملفات والمجلدات العامة للأرشيف القابل للقراءة. هذا العرض لا يستخرج محتويات الأرشيف."
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
            return Err("مجموع الملفات تجاوز حد المعالجة المحلي (512MB).".to_string());
        }
        files.push((archive_path, path, size));
        if files.len() > MAX_FILES {
            return Err(format!("عدد الملفات تجاوز الحد المسموح ({MAX_FILES})."));
        }
    }
    Ok(())
}



fn extract_rpf_entries(
    archive: &RpfArchive,
    data: &[u8],
    start: u32,
    count: u32,
    output: &Path,
    depth: usize,
    files_written: &mut usize,
    total_bytes: &mut u64,
) -> Result<(), String> {
    if depth > 16 {
        return Err("تجاوز عمق أرشيفات RPF الداخلية الحد المسموح (16).".to_string());
    }
    let begin = start as usize;
    let end = begin.checked_add(count as usize)
        .ok_or_else(|| "مدى جدول RPF غير صالح.".to_string())?;
    if end > archive.entries.len() {
        return Err("مدخلات مجلد RPF تشير إلى نطاق خارج جدول الأرشيف.".to_string());
    }
    for entry in &archive.entries[begin..end] {
        validate_rpf_entry_name(&entry.name)?;
        let destination = output.join(&entry.name);
        if !destination.starts_with(output) {
            return Err(format!("مسار عنصر خرج عن مجلد الاستخراج: {}", entry.name));
        }
        match &entry.kind {
            RpfEntryKind::Directory { entries_index, entries_count } => {
                fs::create_dir_all(&destination)
                    .map_err(|error| format!("تعذر إنشاء {}: {error}", destination.display()))?;
                extract_rpf_entries(
                    archive, data, *entries_index, *entries_count, &destination,
                    depth + 1, files_written, total_bytes,
                )?;
            }
            _ => {
                let bytes = archive.extract_entry(data, entry, None)
                    .map_err(|error| format!("تعذر استخراج {}: {error:#}", entry.name))?;
                *total_bytes = total_bytes.saturating_add(bytes.len() as u64);
                if *total_bytes > MAX_INPUT_BYTES {
                    return Err("حجم الملفات بعد الاستخراج تجاوز 512MB.".to_string());
                }
                if *files_written >= MAX_FILES {
                    return Err(format!("عدد الملفات تجاوز الحد المسموح ({MAX_FILES})."));
                }
                if entry.name_lower.ends_with(".rpf") {
                    let nested = RpfArchive::parse(&bytes, &entry.name, None)
                        .map_err(|error| format!("تعذر تحليل الأرشيف الداخلي {}: {error:#}", entry.name))?;
                    ensure_rpf_archive_names_readable(&nested)
                        .map_err(|error| format!("الأرشيف الداخلي {}: {error}", entry.name))?;
                    if nested.version == rpf_archive::RpfVersion::V7 {
                        if nested.encryption.is_encrypted() {
                            return Err(format!("الأرشيف الداخلي {} مشفر ويحتاج مفاتيح اللعبة.", entry.name));
                        }
                        fs::create_dir_all(&destination)
                            .map_err(|error| format!("تعذر إنشاء مجلد الأرشيف الداخلي: {error}"))?;
                        let (nested_start, nested_count) = resolve_rpf_root_range(&nested.entries)
                            .map_err(|error| format!("جذر الأرشيف الداخلي {}: {error}", entry.name))?;
                        extract_rpf_entries(
                            &nested, &bytes, nested_start, nested_count, &destination,
                            depth + 1, files_written, total_bytes,
                        )?;
                    } else {
                        fs::write(&destination, &bytes)
                            .map_err(|error| format!("تعذرت كتابة {}: {error}", destination.display()))?;
                        *files_written += 1;
                    }
                } else {
                    fs::write(&destination, &bytes)
                        .map_err(|error| format!("تعذرت كتابة {}: {error}", destination.display()))?;
                    *files_written += 1;
                }
            }
        }
    }
    Ok(())
}

fn extract_rpf_to_directory(input: &Path, output: &Path) -> Result<(usize, u64, String), String> {
    let metadata = fs::metadata(input)
        .map_err(|error| format!("تعذر قراءة بيانات RPF: {error}"))?;
    if metadata.len() > MAX_INPUT_BYTES {
        return Err("حجم RPF يتجاوز حد المعالجة المحلي (512MB).".to_string());
    }
    if !metadata.is_file() {
        return Err("المصدر المحدد ليس ملفاً.".to_string());
    }
    if output.starts_with(input) {
        return Err("مجلد الاستخراج لا يمكن أن يكون داخل ملف المصدر.".to_string());
    }
    let bytes = fs::read(input)
        .map_err(|error| format!("تعذرت قراءة RPF: {error}"))?;
    let name = input.file_name().and_then(|v| v.to_str()).unwrap_or("archive.rpf");
    let archive = RpfArchive::parse(&bytes, name, None)
        .map_err(|error| format!("تعذر تحليل RPF: {error:#}"))?;
    ensure_rpf_archive_names_readable(&archive)?;
    if !archive_has_vehicle_metadata(&archive) {
        return Err("استخراج RPF متاح لحزم المركبات المدعومة فقط.".to_string());
    }
    if archive.version != rpf_archive::RpfVersion::V7 {
        return Err("الاستخراج المتداخل المحلي في هذه المرحلة يدعم RPF7 فقط.".to_string());
    }
    if archive.encryption.is_encrypted() {
        return Err("هذا الأرشيف مشفر. فك التشفير يحتاج مفاتيح اللعبة الأصلية.".to_string());
    }
    let (start, count) = resolve_rpf_root_range(&archive.entries)?;
    fs::create_dir_all(output)
        .map_err(|error| format!("تعذر إنشاء مجلد الاستخراج: {error}"))?;
    let (mut files_written, mut total_bytes) = (0usize, 0u64);
    extract_rpf_entries(
        &archive, &bytes, start, count, output, 0,
        &mut files_written, &mut total_bytes,
    )?;
    if files_written == 0 {
        return Err("لم يتم استخراج ملفات من هذا الأرشيف.".to_string());
    }
    Ok((files_written, total_bytes, "RPF7".to_string()))
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
    if !contains_vehicle_metadata(&input, 6) {
        return result_error("بناء RPF في INRPF مخصص لمجلدات حزم المركبات.");
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

    fn read_limited<R: Read>(reader: R) -> Result<Vec<u8>, String> {
        let mut limited = reader.take(MAX_RESOURCE_DECOMPRESSED_BYTES + 1);
        let mut output = Vec::new();
        limited.read_to_end(&mut output)
            .map_err(|error| format!("فشل فك ضغط RSC7: {error}"))?;
        if output.len() as u64 > MAX_RESOURCE_DECOMPRESSED_BYTES {
            return Err("حجم مورد RSC7 بعد فك الضغط تجاوز 512MB. أُوقف التحويل لحماية ذاكرة الجهاز.".to_string());
        }
        if output.is_empty() {
            return Err("حمولة RSC7 فارغة بعد فك الضغط.".to_string());
        }
        Ok(output)
    }

    if let Ok(raw) = read_limited(DeflateDecoder::new(payload)) {
        return Ok(raw);
    }
    if let Ok(raw) = read_limited(ZlibDecoder::new(payload)) {
        return Ok(raw);
    }
    if let Ok(raw) = read_limited(GzDecoder::new(payload)) {
        return Ok(raw);
    }
    Err("تعذر فك ضغط RSC7 ضمن الصيغ والحدود المدعومة. لم يتم تعديل الملف.".to_string())
}

fn replace_marker(data: &mut [u8]) -> usize {
    // Exact little-endian constants verified against the reference converter.
    const PC_MARKER: [u8; 8] = [0x96, 0x69, 0x99, 0x99, 0x55, 0x55, 0x55, 0x77];
    const PS4_MARKER: [u8; 8] = [0x96, 0x68, 0x99, 0x99, 0x55, 0x55, 0x55, 0x77];
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
    if !has_vehicle_metadata_near(&input) {
        return result_error("اختر مورداً من مجلد مركبة يحتوي بيانات المركبة.");
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
        return result_error("حجم المورد تجاوز حد المعالجة المحلي (512MB).");
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


fn safe_texture_filename(name: &str, index: usize, hash: u32) -> String {
    let mut cleaned: String = name.chars()
        .map(|ch| if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' { ch } else { '_' })
        .collect();
    while cleaned.contains("__") {
        cleaned = cleaned.replace("__", "_");
    }
    cleaned = cleaned.trim_matches('_').to_string();
    if cleaned.is_empty() {
        cleaned = format!("texture_{index}_{hash:08x}");
    }
    if cleaned.len() > 80 {
        cleaned.truncate(80);
    }
    if !cleaned.to_ascii_lowercase().ends_with(".dds") {
        cleaned.push_str(".dds");
    }
    cleaned
}


fn convert_resource_folder(input: &Path, output: &Path) -> Result<(usize, usize, usize, u64, u64), String> {
    if !input.is_dir() {
        return Err("المصدر المحدد ليس مجلداً.".to_string());
    }
    if output.starts_with(input) || input.starts_with(output) {
        return Err("مجلد الناتج يجب أن يكون خارج مجلد المصدر وغير متداخل معه.".to_string());
    }
    if output.exists() {
        return Err("مجلد الناتج موجود مسبقاً. اختر مجلداً جديداً حتى لا تُستبدل ملفاتك.".to_string());
    }
    let mut files = Vec::new();
    let mut input_bytes = 0u64;
    collect_files(input, input, 0, &mut files, &mut input_bytes)?;
    if files.is_empty() {
        return Err("المجلد المصدر فارغ.".to_string());
    }
    let parent = output.parent().ok_or_else(|| "مسار مجلد الناتج غير صالح.".to_string())?;
    fs::create_dir_all(parent).map_err(|error| format!("تعذر إنشاء مجلد الناتج: {error}"))?;
    let staging = parent.join(format!(".gta-convert-staging-{}", std::process::id()));
    if staging.exists() {
        fs::remove_dir_all(&staging).map_err(|error| format!("تعذر تنظيف مجلد عمل سابق: {error}"))?;
    }
    fs::create_dir_all(&staging).map_err(|error| format!("تعذر إنشاء مجلد العمل: {error}"))?;

    let result = (|| -> Result<(usize, usize, usize, u64, u64), String> {
        let mut converted_count = 0usize;
        let mut copied_count = 0usize;
        let mut patched_markers = 0usize;
        let mut output_bytes = 0u64;
        for (relative, source_path, _) in &files {
            let extension = source_path.extension().and_then(|v| v.to_str()).unwrap_or("").to_ascii_lowercase();
            if extension == "ytd" {
                return Err(format!("توقف التحويل عند {}: يحتاج YTD إلى بناء OTD بصيغة Orbis، وهذا المحرك لم يكتمل بعد. لم يتم اعتماد مجلد ناقص.", relative));
            }
            let source = fs::read(source_path)
                .map_err(|error| format!("تعذرت قراءة {}: {error}", source_path.display()))?;
            let (relative_output, bytes, converted, markers) = if matches!(
                extension.as_str(),
                "yft" | "ydr" | "ydd" | "ypt" | "ybn" | "ybd" | "yld" | "yed" |
                "yfd" | "ynd" | "ynv" | "yvr" | "ywr" | "ypdb" | "ycd" |
                "ymap" | "ytyp" | "ymt" | "ymf"
            ) {
                let (new_extension, output_bytes, patched, mode) = convert_resource_bytes(&extension, &source)?;
                if mode == "extension-only-no-RSC7" {
                    return Err(format!("الملف {} يحمل امتداد .{} لكن لا يحتوي ترويسة RSC7 المطلوبة. أُوقف التحويل بدلاً من تغيير اسمه فقط.", relative, extension));
                }
                let mut path = PathBuf::from(relative);
                path.set_extension(new_extension);
                (path, output_bytes, true, patched)
            } else {
                (PathBuf::from(relative), source, false, 0)
            };
            let destination = staging.join(&relative_output);
            if !destination.starts_with(&staging) {
                return Err(format!("مسار ناتج غير آمن: {}", relative_output.display()));
            }
            if let Some(dir) = destination.parent() {
                fs::create_dir_all(dir).map_err(|error| format!("تعذر إنشاء {}: {error}", dir.display()))?;
            }
            fs::write(&destination, &bytes)
                .map_err(|error| format!("تعذرت كتابة {}: {error}", destination.display()))?;
            output_bytes = output_bytes.saturating_add(bytes.len() as u64);
            if converted {
                converted_count += 1;
                patched_markers += markers;
            } else {
                copied_count += 1;
            }
        }
        if converted_count == 0 {
            return Err("لم يتم العثور على موارد Y* مدعومة للتحويل في المجلد.".to_string());
        }
        fs::rename(&staging, output)
            .map_err(|error| format!("تعذر اعتماد مجلد التحويل النهائي: {error}"))?;
        Ok((converted_count, copied_count, patched_markers, input_bytes, output_bytes))
    })();

    if result.is_err() {
        let _ = fs::remove_dir_all(&staging);
    }
    result
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_convert_folder(
    input_directory: *const c_char,
    output_directory: *const c_char,
) -> *mut c_char {
    let input = match read_c_path(input_directory) {
        Ok(value) => PathBuf::from(value),
        Err(error) => return result_error(error),
    };
    let output = match read_c_path(output_directory) {
        Ok(value) => PathBuf::from(value),
        Err(error) => return result_error(error),
    };
    if !has_vehicle_metadata_near(&input) {
        return result_error("اختر مجلد مورد مركبة يحتوي بيانات المركبة.");
    }
    match convert_resource_folder(&input, &output) {
        Ok((converted, copied, markers, input_bytes, output_bytes)) => result_ok(json!({
            "ok": true,
            "converted_resources": converted,
            "copied_files": copied,
            "patched_markers": markers,
            "input_bytes": input_bytes,
            "output_bytes": output_bytes,
            "output": output.to_string_lossy(),
            "warning": "تم تحويل الموارد البنيوية المدعومة ونسخ الملفات الأخرى. أي YTD يوقف العملية لأن OTD Orbis لم يكتمل بعد؛ لا تعتبر الناتج DLC نهائياً."
        })),
        Err(error) => result_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_convert_fivem_resource(
    input_directory: *const c_char,
    output_directory: *const c_char,
) -> *mut c_char {
    let input = match read_c_path(input_directory) {
        Ok(value) => PathBuf::from(value),
        Err(error) => return result_error(error),
    };
    let output = match read_c_path(output_directory) {
        Ok(value) => PathBuf::from(value),
        Err(error) => return result_error(error),
    };
    if !input.is_dir() {
        return result_error("مورد FiveM يجب أن يكون مجلداً مستورداً أو أرشيفاً مفكوكاً.");
    }
    if !has_fivem_manifest(&input) {
        return result_error("لم يتم العثور على fxmanifest.lua أو __resource.lua في جذر المورد.");
    }
    if !has_vehicle_metadata_near(&input) {
        return result_error("المحرك المحلي الحالي يحوّل موارد المركبات فقط؛ لم يتم العثور على بيانات مركبة.");
    }
    match convert_resource_folder(&input, &output) {
        Ok((converted, copied, markers, input_bytes, output_bytes)) => result_ok(json!({
            "ok": true,
            "engine": "INRPF FiveM Resource Engine",
            "converted_resources": converted,
            "copied_files": copied,
            "patched_markers": markers,
            "input_bytes": input_bytes,
            "output_bytes": output_bytes,
            "output": output.to_string_lossy(),
            "warning": "تم تحويل موارد RSC7 المدعومة فقط ونسخ الملفات الأخرى كما هي. ملفات YTD توقف العملية حالياً لأن بناء OTD الخاص بـOrbis غير مكتمل. ملفات Lua وNUI وموارد السيرفر ليست تطبيقات PS4 ولا تُنفذ على الجهاز. الناتج ليس DLC نهائياً حتى يُبنى ويُختبر داخل حزمة Orbx."
        })),
        Err(error) => result_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_extract_ytd(
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
        return result_error("ملف YTD المحدد غير موجود.");
    }
    if !has_vehicle_metadata_near(&input) {
        return result_error("استخراج YTD متاح لخامات حزم المركبات فقط.");
    }
    let metadata = match fs::metadata(&input) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذر قراءة بيانات YTD: {error}")),
    };
    if metadata.len() > MAX_INPUT_BYTES {
        return result_error("حجم YTD تجاوز حد المعالجة المحلي (512MB).");
    }
    let bytes = match fs::read(&input) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذرت قراءة YTD: {error}")),
    };
    let textures = match rage_formats::parse_ytd(&bytes) {
        Ok(value) => value,
        Err(error) => return result_error(format!("تعذر تحليل قاموس الخامات YTD: {error:#}")),
    };
    if textures.is_empty() {
        return result_error("تم فتح YTD لكن لم يتم العثور على خامات قابلة للاستخراج.");
    }
    if let Err(error) = fs::create_dir_all(&output_dir) {
        return result_error(format!("تعذر إنشاء مجلد الخامات: {error}"));
    }

    let mut written = 0usize;
    let mut total_bytes = 0u64;
    let mut summaries = Vec::new();
    let mut used_names = std::collections::HashSet::new();

    for (index, texture) in textures.iter().enumerate() {
        if texture.pixel_data.is_empty() || texture.format == rage_formats::TextureFormat::Unknown {
            continue;
        }
        let mut name = safe_texture_filename(&texture.name, index, texture.name_hash);
        if !used_names.insert(name.to_ascii_lowercase()) {
            let stem = Path::new(&name).file_stem().and_then(|v| v.to_str()).unwrap_or("texture");
            name = format!("{stem}_{:08x}_{index}.dds", texture.name_hash);
            used_names.insert(name.to_ascii_lowercase());
        }
        let dds = texture.to_dds();
        if dds.len() < 128 {
            continue;
        }
        let output = output_dir.join(&name);
        let temp = output_dir.join(format!(".{name}.tmp"));
        let write_result = (|| -> Result<(), String> {
            let mut file = fs::File::create(&temp).map_err(|error| format!("تعذر إنشاء DDS: {error}"))?;
            file.write_all(&dds).map_err(|error| format!("تعذرت كتابة DDS: {error}"))?;
            file.sync_all().map_err(|error| format!("تعذر حفظ DDS: {error}"))?;
            fs::rename(&temp, &output).map_err(|error| format!("تعذر اعتماد DDS: {error}"))?;
            Ok(())
        })();
        if let Err(error) = write_result {
            let _ = fs::remove_file(&temp);
            return result_error(error);
        }
        written += 1;
        total_bytes = total_bytes.saturating_add(dds.len() as u64);
        if summaries.len() < 30 {
            summaries.push(json!({
                "name": name,
                "width": texture.width,
                "height": texture.height,
                "format": texture.format.to_string(),
                "mip_levels": texture.levels,
                "bytes": dds.len()
            }));
        }
    }

    if written == 0 {
        return result_error("تم تحليل YTD لكن لم تُنتج أي ملفات DDS صالحة.");
    }
    result_ok(json!({
        "ok": true,
        "textures_found": textures.len(),
        "textures_exported": written,
        "output_bytes": total_bytes,
        "output_directory": output_dir.to_string_lossy(),
        "items_preview": summaries,
        "warning": "تم استخراج الخامات إلى DDS فقط. لم يتم إنشاء OTD أو تحويل ضغط الخامات إلى صيغة PS4."
    }))
}


fn texture_name(path: &Path) -> Result<String, String> {
    let name = path.file_stem().and_then(|value| value.to_str())
        .ok_or_else(|| format!("اسم خامة غير صالح: {}", path.display()))?;
    let name = name.trim();
    if name.is_empty() || name.len() > 120 {
        return Err(format!("اسم الخامة فارغ أو أطول من 120 حرفاً: {}", path.display()));
    }
    Ok(name.to_string())
}

fn build_ytd_from_folder(input: &Path) -> Result<(Vec<u8>, usize, u64), String> {
    if !input.is_dir() {
        return Err("المصدر المحدد ليس مجلداً.".to_string());
    }
    let mut files = Vec::new();
    let mut total_bytes = 0u64;
    collect_files(input, input, 0, &mut files, &mut total_bytes)?;
    let mut textures = Vec::new();
    let mut skipped = Vec::new();

    for (_, path, size) in files {
        let extension = path.extension().and_then(|value| value.to_str())
            .unwrap_or("").to_ascii_lowercase();
        if !matches!(extension.as_str(), "dds" | "png" | "jpg" | "jpeg" | "webp" | "bmp" | "tga") {
            continue;
        }
        if size > 128 * 1024 * 1024 {
            return Err(format!("ملف الخامة أكبر من 128MB: {}", path.display()));
        }
        let name = texture_name(&path)?;
        let bytes = fs::read(&path)
            .map_err(|error| format!("تعذرت قراءة الخامة {}: {error}", path.display()))?;

        let texture = if extension == "dds" {
            let mut texture = rage_formats::parse_dds(&bytes)
                .map_err(|error| format!("ملف DDS غير مدعوم ({}): {error:#}", path.display()))?;
            texture.name = name.clone();
            texture.name_hash = rage_formats::rage_joaat(&name.to_ascii_lowercase());
            texture
        } else {
            let decoded = image::load_from_memory(&bytes)
                .map_err(|error| format!("تعذر فك الصورة {}: {error}", path.display()))?;
            let (width, height) = (decoded.width(), decoded.height());
            if width == 0 || height == 0 || width > 8192 || height > 8192 {
                return Err(format!("أبعاد الصورة غير مدعومة: {width}x{height} ({})", path.display()));
            }
            let rgba = decoded.to_rgba8();
            let format = rage_formats::auto_format(&name, rgba.as_raw());
            let format = if format.texture_format().is_block_compressed() && (width % 4 != 0 || height % 4 != 0) {
                rage_formats::EncodeFormat::Rgba8
            } else {
                format
            };
            rage_formats::encode_texture(&name, rgba.as_raw(), width, height, format, None)
                .map_err(|error| format!("فشل ترميز الخامة {}: {error:#}", path.display()))?
        };
        if texture.pixel_data.is_empty() {
            skipped.push(path.display().to_string());
            continue;
        }
        textures.push(texture);
        if textures.len() > 4096 {
            return Err("عدد الخامات تجاوز الحد المسموح (4096).".to_string());
        }
    }

    if textures.is_empty() {
        return Err("ما لقيت خامات DDS أو صور مدعومة داخل المجلد.".to_string());
    }

    let mut hashes = std::collections::HashSet::new();
    for texture in &textures {
        if !hashes.insert(texture.name_hash) {
            return Err(format!("فيه أسماء خامات متكررة أو متصادمة في JOAAT: {}", texture.name));
        }
    }

    let expected_count = textures.len();
    let output = rage_formats::serialize_ytd(&textures)
        .map_err(|error| format!("فشل بناء قاموس YTD: {error:#}"))?;
    let parsed = rage_formats::parse_ytd(&output)
        .map_err(|error| format!("فشل فحص قاموس YTD الناتج: {error:#}"))?;
    if parsed.len() != expected_count {
        return Err(format!("فشل التحقق: دخلت {expected_count} خامة لكن الناتج يحتوي {} فقط.", parsed.len()));
    }
    Ok((output, expected_count, total_bytes))
}

#[no_mangle]
pub unsafe extern "C" fn gta_engine_build_ytd(
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
    if !has_vehicle_metadata_near(&input) {
        return result_error("بناء YTD متاح لمجلدات خامات المركبات فقط.");
    }
    if output.starts_with(&input) {
        return result_error("احفظ قاموس YTD خارج مجلد الخامات المصدرية.");
    }
    let (bytes, texture_count, input_bytes) = match build_ytd_from_folder(&input) {
        Ok(value) => value,
        Err(error) => return result_error(error),
    };
    if let Some(parent) = output.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return result_error(format!("تعذر إنشاء مجلد الناتج: {error}"));
        }
    }
    let temp = output.with_extension("ytd.tmp");
    let write_result = (|| -> Result<(), String> {
        let mut file = fs::File::create(&temp)
            .map_err(|error| format!("تعذر إنشاء ملف YTD مؤقت: {error}"))?;
        file.write_all(&bytes).map_err(|error| format!("تعذرت كتابة YTD: {error}"))?;
        file.sync_all().map_err(|error| format!("تعذر حفظ YTD: {error}"))?;
        fs::rename(&temp, &output).map_err(|error| format!("تعذر اعتماد YTD النهائي: {error}"))?;
        Ok(())
    })();
    if let Err(error) = write_result {
        let _ = fs::remove_file(&temp);
        return result_error(error);
    }
    result_ok(json!({
        "ok": true,
        "format": "YTD",
        "textures": texture_count,
        "input_bytes": input_bytes,
        "output_bytes": bytes.len(),
        "output": output.to_string_lossy(),
        "validated_textures": texture_count,
        "warning": "هذا قاموس YTD بصيغة PC Legacy، وليس OTD خاصاً بـPS4. بناء OTD يتطلب تخطيط Orbis والتحقق من ملفات PS4 حقيقية."
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use rpf_archive::{RpfArchive, RpfBuilder, RpfEncryption};

    #[test]
    fn encrypted_rpf_toc_is_rejected_before_using_corrupt_names() {
        let mut builder = RpfBuilder::new(RpfEncryption::Open);
        builder.add_file("Rbtitt/dlc.rpf", b"fixture".to_vec());
        let bytes = builder.build(None).expect("build fixture");
        let mut archive = RpfArchive::parse(&bytes, "encrypted-fixture.rpf", None).unwrap();
        archive.encryption = RpfEncryption::Ng;
        let error = ensure_rpf_archive_names_readable(&archive).unwrap_err();
        assert!(error.contains("فهرس RPF مشفر"));
        assert!(error.contains("مفاتيح فك التشفير"));
    }

    #[test]
    fn corrupted_rpf_name_is_reported_as_encoding_error_not_path_traversal() {
        let mut builder = RpfBuilder::new(RpfEncryption::Open);
        builder.add_file("Rbtitt/dlc.rpf", b"fixture".to_vec());
        let bytes = builder.build(None).expect("build fixture");
        let mut archive = RpfArchive::parse(&bytes, "corrupt-name.rpf", None).unwrap();
        let entry = archive.entries.iter_mut().find(|entry| entry.name == "Rbtitt").unwrap();
        entry.name = "Rbtitt\u{FFFD}\u{000C}".to_string();
        let error = ensure_rpf_archive_names_readable(&archive).unwrap_err();
        assert!(error.contains("ترميزه غير صالح"));
        assert!(!error.contains("غير آمن داخل RPF"));
    }

    #[test]
    fn valid_rbtitt_rpf_names_are_accepted() {
        let mut builder = RpfBuilder::new(RpfEncryption::Open);
        builder.add_file("Rbtitt/dlc.rpf", b"fixture".to_vec());
        let bytes = builder.build(None).expect("build fixture");
        let archive = RpfArchive::parse(&bytes, "valid-name.rpf", None).unwrap();
        ensure_rpf_archive_names_readable(&archive).unwrap();
        assert!(validate_rpf_entry_name("Rbtitt").is_ok());
    }

    #[test]
    fn resolves_flat_rpf_root_without_directory_wrapper() {
        let entries = vec![
            rpf_archive::RpfEntry {
                name: "vehicles.meta".to_string(),
                name_lower: "vehicles.meta".to_string(),
                kind: RpfEntryKind::BinaryFile {
                    file_offset: 1, file_size: 0, uncompressed_size: 16, is_encrypted: false,
                },
            },
            rpf_archive::RpfEntry {
                name: "demo.yft".to_string(),
                name_lower: "demo.yft".to_string(),
                kind: RpfEntryKind::ResourceFile {
                    file_offset: 2, file_size: 32, system_flags: 0, graphics_flags: 0, is_encrypted: false,
                },
            },
        ];
        assert_eq!(resolve_rpf_root_range(&entries).unwrap(), (0, 2));
    }

    #[test]
    fn resolves_standard_rpf_root_directory() {
        let entries = vec![
            rpf_archive::RpfEntry {
                name: String::new(),
                name_lower: String::new(),
                kind: RpfEntryKind::Directory { entries_index: 1, entries_count: 1 },
            },
            rpf_archive::RpfEntry {
                name: "vehicles.meta".to_string(),
                name_lower: "vehicles.meta".to_string(),
                kind: RpfEntryKind::BinaryFile {
                    file_offset: 1, file_size: 0, uncompressed_size: 16, is_encrypted: false,
                },
            },
        ];
        assert_eq!(resolve_rpf_root_range(&entries).unwrap(), (1, 1));
    }

    #[test]
    fn rejects_ambiguous_root_with_unattached_subdirectories() {
        let entries = vec![
            rpf_archive::RpfEntry {
                name: "vehicles.meta".to_string(),
                name_lower: "vehicles.meta".to_string(),
                kind: RpfEntryKind::BinaryFile {
                    file_offset: 1, file_size: 0, uncompressed_size: 16, is_encrypted: false,
                },
            },
            rpf_archive::RpfEntry {
                name: "stream".to_string(),
                name_lower: "stream".to_string(),
                kind: RpfEntryKind::Directory { entries_index: 2, entries_count: 1 },
            },
            rpf_archive::RpfEntry {
                name: "demo.yft".to_string(),
                name_lower: "demo.yft".to_string(),
                kind: RpfEntryKind::ResourceFile {
                    file_offset: 2, file_size: 32, system_flags: 0, graphics_flags: 0, is_encrypted: false,
                },
            },
        ];
        assert!(resolve_rpf_root_range(&entries).is_err());
    }

    #[test]
    fn accepts_normal_rpf_entry_names_and_rejects_path_traversal() {
        assert!(validate_rpf_entry_name("Rbtitt").is_ok());
        assert!(validate_rpf_entry_name("rb3nasb").is_ok());
        assert!(validate_rpf_entry_name("vehicle_2026").is_ok());
        assert!(validate_rpf_entry_name("car model").is_ok());
        assert!(validate_rpf_entry_name("../escape").is_err());
        assert!(validate_rpf_entry_name("folder\\\\escape").is_err());
        assert!(validate_rpf_entry_name(".").is_err());
        assert!(validate_rpf_entry_name("..").is_err());
        assert!(validate_rpf_entry_name("bad\\nname").is_err());
    }

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
        assert_eq!(extracted.as_slice(), expected);
    }

    #[test]
    fn probes_valid_non_vehicle_rpf_without_rejecting_it() {
        use std::ffi::CString;

        let root = std::env::temp_dir().join(format!("inrpf-generic-rpf-probe-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();

        let mut builder = RpfBuilder::new(RpfEncryption::Open);
        builder.add_file("common/data/readme.txt", b"generic archive".to_vec());
        let bytes = builder.build(None).expect("build generic RPF7");
        let path = root.join("generic.rpf");
        fs::write(&path, bytes).unwrap();

        let path_c = CString::new(path.to_str().unwrap()).unwrap();
        let response = unsafe { gta_engine_probe_rpf(path_c.as_ptr()) };
        assert!(!response.is_null(), "RPF probe returned a null response");
        let response_text = unsafe { CStr::from_ptr(response).to_str().unwrap().to_owned() };
        unsafe { gta_engine_free_string(response) };
        let payload: serde_json::Value = serde_json::from_str(&response_text).unwrap();

        assert_eq!(payload["ok"], true, "generic RPF must be inspectable");
        assert_eq!(payload["format"], "RPF7");
        assert_eq!(payload["has_vehicle_metadata"], false);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn detects_fivem_resource_manifest_files() {
        let root = std::env::temp_dir().join(format!("inrpf-fivem-manifest-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        assert!(!has_fivem_manifest(&root));
        fs::write(root.join("fxmanifest.lua"), "game 'gta5'").unwrap();
        assert!(has_fivem_manifest(&root));
        fs::remove_file(root.join("fxmanifest.lua")).unwrap();
        fs::write(root.join("__resource.lua"), "resource_manifest_version '44febabe-d386-4d18-afbe-5e627f4af937'").unwrap();
        assert!(has_fivem_manifest(&root));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn lists_complete_rpf_tree_without_extracting() {
        let mut builder = RpfBuilder::new(RpfEncryption::Open);
        builder.add_file("common/data/vehicles.meta", b"<vehicles/>".to_vec());
        builder.add_file("stream/cars/demo.yft", b"MODEL".to_vec());
        let bytes = builder.build(None).unwrap();
        let parsed = RpfArchive::parse(&bytes, "listing.rpf", None).unwrap();
        let root = parsed.entries.first().unwrap();
        let (start, count) = match &root.kind {
            RpfEntryKind::Directory { entries_index, entries_count } => (*entries_index, *entries_count),
            _ => panic!("RPF root is not a directory"),
        };
        let mut items = Vec::new();
        collect_rpf_listing(&parsed, start, count, "", 0, &mut items).unwrap();
        let paths = items.iter().filter_map(|item| item["path"].as_str()).collect::<Vec<_>>();
        assert_eq!(paths, vec!["common", "common/data", "common/data/vehicles.meta", "stream", "stream/cars", "stream/cars/demo.yft"]);
        assert_eq!(items.iter().find(|item| item["path"] == "common/data/vehicles.meta").unwrap()["kind"], "vehicle_metadata");
    }

    #[test]
    fn extracts_open_rpf7_to_safe_directory() {
        let root = std::env::temp_dir().join(format!("gta-engine-rpf-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let input = root.join("input");
        let output = root.join("output");
        fs::create_dir_all(&input).unwrap();
        fs::write(input.join("vehicles.meta"), b"<vehicles/>").unwrap();
        let mut builder = RpfBuilder::new(RpfEncryption::Open);
        builder.add_file("common/data/vehicles.meta", b"<vehicles/>".to_vec());
        builder.add_file("common/levels/demo.yft", b"MODEL".to_vec());
        let bytes = builder.build(None).unwrap();
        let archive_path = root.join("test.rpf");
        fs::write(&archive_path, bytes).unwrap();
        let result = extract_rpf_to_directory(&archive_path, &output).unwrap();
        assert_eq!(result.0, 2);
        assert_eq!(fs::read(output.join("common/data/vehicles.meta")).unwrap(), b"<vehicles/>");
        assert_eq!(fs::read(output.join("common/levels/demo.yft")).unwrap(), b"MODEL");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn patches_rsc7_structural_marker_and_preserves_header() {
        use flate2::write::DeflateEncoder;
        use flate2::Compression;
        use std::io::Write;

        let pc = [0x96, 0x69, 0x99, 0x99, 0x55, 0x55, 0x55, 0x77];
        let ps4 = [0x96, 0x68, 0x99, 0x99, 0x55, 0x55, 0x55, 0x77];
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
    fn copies_extension_only_resource_types_without_modifying_bytes() {
        let source = b"YMAP-TEST-DATA";
        let (extension, output, patched, mode) = convert_resource_bytes("ymap", source).unwrap();
        assert_eq!(extension, "omap");
        assert_eq!(output, source);
        assert_eq!(patched, 0);
        assert_eq!(mode, "extension-only");
    }

    #[test]
    fn builds_dds_header_from_parsed_texture_data() {
        let texture = rage_formats::YtdTexture {
            name: "test_texture".to_string(),
            name_hash: 1,
            width: 4,
            height: 4,
            depth: 1,
            format: rage_formats::TextureFormat::DXT1,
            levels: 1,
            stride: 2,
            pixel_data: vec![0u8; 8],
        };
        let dds = texture.to_dds();
        assert_eq!(&dds[..4], b"DDS ");
        assert_eq!(dds.len(), 128 + 8);
    }

    #[test]
    fn keeps_initial_resource_port_focused_on_vehicle_assets() {
        assert!(resource_mapping("yft").is_ok());
        assert!(resource_mapping("ydr").is_ok());
        assert_eq!(resource_mapping("ypt").unwrap().0, "opt");
        assert_eq!(resource_mapping("yed").unwrap().0, "oed");
        assert_eq!(resource_mapping("ynv").unwrap().0, "onv");
        assert_eq!(resource_mapping("ypdb").unwrap().0, "opdb");
    }

    #[test]
    fn batch_conversion_preserves_folders_and_copies_other_files() {
        use flate2::write::DeflateEncoder;
        use flate2::Compression;
        use std::io::Write;
        let root = std::env::temp_dir().join(format!("gta-engine-batch-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let input = root.join("input");
        let output = root.join("output");
        fs::create_dir_all(input.join("stream")).unwrap();
        fs::write(input.join("common.xml"), b"<meta/>").unwrap();
        let mut encoder = DeflateEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(b"synthetic model payload").unwrap();
        let compressed = encoder.finish().unwrap();
        let mut rsc = Vec::from(&b"RSC7"[..]);
        rsc.extend_from_slice(&13u32.to_le_bytes());
        rsc.extend_from_slice(&0u32.to_le_bytes());
        rsc.extend_from_slice(&0u32.to_le_bytes());
        rsc.extend_from_slice(&compressed);
        fs::write(input.join("stream/car.yft"), rsc).unwrap();
        let result = convert_resource_folder(&input, &output).unwrap();
        assert_eq!(result.0, 1);
        assert_eq!(result.1, 1);
        assert!(output.join("stream/car.oft").exists());
        assert_eq!(fs::read(output.join("common.xml")).unwrap(), b"<meta/>");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn batch_conversion_refuses_ytd_without_orbis_otd_builder() {
        let root = std::env::temp_dir().join(format!("gta-engine-ytd-batch-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let input = root.join("input");
        let output = root.join("output");
        fs::create_dir_all(&input).unwrap();
        fs::write(input.join("vehicle.ytd"), b"YTD").unwrap();
        let error = convert_resource_folder(&input, &output).unwrap_err();
        assert!(error.contains("Orbis"));
        assert!(!output.exists());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn builds_and_roundtrips_ytd_from_dds_texture() {
        let texture = rage_formats::encode_texture(
            "test_diffuse",
            &vec![255u8; 4 * 4 * 4],
            4,
            4,
            rage_formats::EncodeFormat::Bc1,
            Some(1),
        ).unwrap();
        let ytd = rage_formats::serialize_ytd(&[texture]).unwrap();
        let parsed = rage_formats::parse_ytd(&ytd).unwrap();
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].name, "test_diffuse");
        assert_eq!(parsed[0].width, 4);
        assert_eq!(parsed[0].height, 4);
    }

    #[test]
    fn refuses_ytd_until_native_otd_builder_exists() {
        let error = convert_resource_bytes("ytd", b"not a ytd").unwrap_err();
        assert!(error.contains("OTD"));
    }
}


// MARK: - Native FTP transport (SuppaFTP over Rust std::net)

fn ftp_open(host: &str, port: u16, username: &str, password: &str) -> Result<FtpStream, String> {
    let mut client = FtpStream::connect((host, port))
        .map_err(|error| format!("تعذر فتح اتصال FTP إلى {host}:{port}: {error}"))?;
    client.set_mode(Mode::Passive);
    // GoldHEN and console FTP servers may advertise 0.0.0.0 or an unreachable
    // interface in PASV. Reuse the control peer address and keep the PASV port.
    client.set_passive_nat_workaround(true);
    client.get_ref().set_read_timeout(Some(std::time::Duration::from_secs(25)))
        .map_err(|error| format!("تعذر ضبط مهلة قراءة FTP: {error}"))?;
    client.get_ref().set_write_timeout(Some(std::time::Duration::from_secs(25)))
        .map_err(|error| format!("تعذر ضبط مهلة إرسال FTP: {error}"))?;
    client.login(username, password)
        .map_err(|error| format!("اتصال TCP نجح لكن تسجيل دخول FTP فشل: {error}"))?;
    client.transfer_type(FileType::Binary)
        .map_err(|error| format!("تعذر تفعيل النقل الثنائي FTP: {error}"))?;
    Ok(client)
}

#[no_mangle]
pub unsafe extern "C" fn gta_ftp_connect(
    host: *const c_char, port: u16, username: *const c_char, password: *const c_char
) -> *mut c_char {
    let host = match read_c_path(host) { Ok(v) => v, Err(e) => return result_error(e) };
    let username = match read_c_path(username) { Ok(v) => v, Err(e) => return result_error(e) };
    let password = match read_c_path(password) { Ok(v) => v, Err(e) => return result_error(e) };
    match ftp_open(host, port, username, password) {
        Ok(mut ftp) => {
            let welcome = ftp.get_welcome_msg().unwrap_or("").to_string();
            let cwd = ftp.pwd().unwrap_or_else(|_| "/".to_string());
            let _ = ftp.quit();
            result_ok(json!({"ok":true,"welcome":welcome,"path":cwd,"transport":"suppaftp/std::net"}))
        }
        Err(error) => result_error(error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn gta_ftp_list(
    host: *const c_char, port: u16, username: *const c_char, password: *const c_char,
    remote_path: *const c_char
) -> *mut c_char {
    let host = match read_c_path(host) { Ok(v) => v, Err(e) => return result_error(e) };
    let username = match read_c_path(username) { Ok(v) => v, Err(e) => return result_error(e) };
    let password = match read_c_path(password) { Ok(v) => v, Err(e) => return result_error(e) };
    let remote_path = match read_c_path(remote_path) { Ok(v) => v, Err(e) => return result_error(e) };
    let mut ftp = match ftp_open(host, port, username, password) { Ok(v) => v, Err(e) => return result_error(e) };
    if let Err(error) = ftp.cwd(remote_path) {
        return result_error(format!("تعذر فتح المسار {remote_path}: {error}"));
    }

    let entries = match ftp.mlsd(None) {
        Ok(lines) => lines.into_iter().filter_map(|line| {
            let (facts, name) = line.split_once(' ')?;
            let name = name.trim();
            if name.is_empty() || name == "." || name == ".." { return None; }
            let lower = facts.to_ascii_lowercase();
            let is_dir = lower.contains("type=dir");
            let size = facts.split(';').find_map(|fact| fact.strip_prefix("size=")).unwrap_or("");
            Some(json!({"name":name,"isDirectory":is_dir,"size":size}))
        }).collect::<Vec<_>>(),
        Err(_) => match ftp.list(None) {
            Ok(lines) => lines.into_iter().filter_map(|line| {
                let parts = line.split_whitespace().collect::<Vec<_>>();
                if parts.len() < 9 { return None; }
                let name = parts[8..].join(" ");
                if name.is_empty() || name == "." || name == ".." { return None; }
                let is_dir = parts[0].starts_with('d');
                let size = if is_dir { String::new() } else { parts[4].to_string() };
                Some(json!({"name":name,"isDirectory":is_dir,"size":size}))
            }).collect::<Vec<_>>(),
            Err(error) => return result_error(format!("فشل MLSD وLIST للمسار {remote_path}: {error}")),
        }
    };
    let _ = ftp.quit();
    result_ok(json!({"ok":true,"entries":entries,"path":remote_path}))
}

#[no_mangle]
pub unsafe extern "C" fn gta_ftp_mkdir(
    host: *const c_char, port: u16, username: *const c_char, password: *const c_char,
    remote_path: *const c_char, folder_name: *const c_char
) -> *mut c_char {
    let host = match read_c_path(host) { Ok(v) => v, Err(e) => return result_error(e) };
    let username = match read_c_path(username) { Ok(v) => v, Err(e) => return result_error(e) };
    let password = match read_c_path(password) { Ok(v) => v, Err(e) => return result_error(e) };
    let remote_path = match read_c_path(remote_path) { Ok(v) => v, Err(e) => return result_error(e) };
    let folder_name = match read_c_path(folder_name) { Ok(v) => v, Err(e) => return result_error(e) };
    if folder_name.contains('/') || folder_name.contains('\\') || folder_name.contains("..") {
        return result_error("اسم المجلد غير صالح.");
    }
    let mut ftp = match ftp_open(host, port, username, password) { Ok(v) => v, Err(e) => return result_error(e) };
    if let Err(error) = ftp.cwd(remote_path) { return result_error(format!("تعذر فتح المسار: {error}")); }
    if let Err(error) = ftp.mkdir(folder_name) { return result_error(format!("تعذر إنشاء المجلد: {error}")); }
    let _ = ftp.quit();
    result_ok(json!({"ok":true}))
}

#[no_mangle]
pub unsafe extern "C" fn gta_ftp_upload(
    host: *const c_char, port: u16, username: *const c_char, password: *const c_char,
    remote_path: *const c_char, remote_name: *const c_char, local_path: *const c_char
) -> *mut c_char {
    let host = match read_c_path(host) { Ok(v) => v, Err(e) => return result_error(e) };
    let username = match read_c_path(username) { Ok(v) => v, Err(e) => return result_error(e) };
    let password = match read_c_path(password) { Ok(v) => v, Err(e) => return result_error(e) };
    let remote_path = match read_c_path(remote_path) { Ok(v) => v, Err(e) => return result_error(e) };
    let remote_name = match read_c_path(remote_name) { Ok(v) => v, Err(e) => return result_error(e) };
    let local_path = match read_c_path(local_path) { Ok(v) => v, Err(e) => return result_error(e) };
    if remote_name.contains('/') || remote_name.contains('\\') || remote_name.contains("..") {
        return result_error("اسم الملف البعيد غير صالح.");
    }
    let mut ftp = match ftp_open(host, port, username, password) { Ok(v) => v, Err(e) => return result_error(e) };
    if let Err(error) = ftp.cwd(remote_path) { return result_error(format!("تعذر فتح مجلد الرفع: {error}")); }
    let mut input = match fs::File::open(local_path) {
        Ok(file) => file,
        Err(error) => return result_error(format!("تعذر فتح الملف المحلي: {error}")),
    };
    let bytes = match ftp.put_file(remote_name, &mut input) {
        Ok(bytes) => bytes,
        Err(error) => return result_error(format!("فشل رفع الملف عبر FTP: {error}")),
    };
    let _ = ftp.quit();
    result_ok(json!({"ok":true,"bytes":bytes}))
}

#[no_mangle]
pub unsafe extern "C" fn gta_ftp_download(
    host: *const c_char, port: u16, username: *const c_char, password: *const c_char,
    remote_path: *const c_char, remote_name: *const c_char, local_path: *const c_char
) -> *mut c_char {
    let host = match read_c_path(host) { Ok(v) => v, Err(e) => return result_error(e) };
    let username = match read_c_path(username) { Ok(v) => v, Err(e) => return result_error(e) };
    let password = match read_c_path(password) { Ok(v) => v, Err(e) => return result_error(e) };
    let remote_path = match read_c_path(remote_path) { Ok(v) => v, Err(e) => return result_error(e) };
    let remote_name = match read_c_path(remote_name) { Ok(v) => v, Err(e) => return result_error(e) };
    let local_path = match read_c_path(local_path) { Ok(v) => v, Err(e) => return result_error(e) };
    let mut ftp = match ftp_open(host, port, username, password) { Ok(v) => v, Err(e) => return result_error(e) };
    if let Err(error) = ftp.cwd(remote_path) { return result_error(format!("تعذر فتح مجلد التنزيل: {error}")); }
    let destination = Path::new(local_path);
    if let Some(parent) = destination.parent() {
        if let Err(error) = fs::create_dir_all(parent) { return result_error(format!("تعذر إنشاء مجلد التنزيل: {error}")); }
    }
    let mut output = match fs::File::create(destination) {
        Ok(file) => file,
        Err(error) => return result_error(format!("تعذر إنشاء الملف المحلي: {error}")),
    };
    let transfer = ftp.retr(remote_name, |stream| {
        std::io::copy(stream, &mut output).map_err(FtpError::ConnectionError)
    });
    let bytes = match transfer {
        Ok(bytes) => bytes,
        Err(error) => {
            let _ = fs::remove_file(destination);
            return result_error(format!("فشل تنزيل الملف عبر FTP: {error}"));
        }
    };
    let _ = ftp.quit();
    result_ok(json!({"ok":true,"bytes":bytes}))
}
