use rpf_archive::{RpfArchive, RpfEntryKind};
use serde_json::{json, Value};
use std::{env, fs, path::{Path, PathBuf}};

fn safe_name(name: &str) -> Result<(), String> {
    if name.is_empty() || name == "." || name == ".."
        || name.contains('/') || name.contains('\\') || name.contains(':')
        || name.chars().any(|c| c.is_control()) {
        return Err(format!("Unsafe RPF entry name: {name:?}"));
    }
    Ok(())
}

fn walk_rpf(
    archive: &RpfArchive,
    bytes: &[u8],
    start: u32,
    count: u32,
    prefix: &str,
    output: &Path,
    rows: &mut Vec<Value>,
) -> Result<(), String> {
    let begin = start as usize;
    let end = begin.checked_add(count as usize).ok_or("RPF entry range overflow")?;
    if end > archive.entries.len() {
        return Err(format!("RPF entry range {begin}..{end} exceeds {} entries", archive.entries.len()));
    }
    for entry in &archive.entries[begin..end] {
        safe_name(&entry.name)?;
        let rel = if prefix.is_empty() { entry.name.clone() } else { format!("{prefix}/{}", entry.name) };
        match &entry.kind {
            RpfEntryKind::Directory { entries_index, entries_count } => {
                let dir = output.join(&rel);
                fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
                walk_rpf(archive, bytes, *entries_index, *entries_count, &rel, output, rows)?;
            }
            _ => {
                let data = archive.extract_entry(bytes, entry, None)
                    .map_err(|e| format!("extract {rel}: {e:#}"))?;
                let destination = output.join(&rel);
                if !destination.starts_with(output) { return Err(format!("Path escaped output: {rel}")); }
                if let Some(parent) = destination.parent() {
                    fs::create_dir_all(parent).map_err(|e| format!("create parent: {e}"))?;
                }
                fs::write(&destination, &data).map_err(|e| format!("write {rel}: {e}"))?;
                rows.push(json!({
                    "path": rel,
                    "bytes": data.len(),
                    "extension": destination.extension().and_then(|x| x.to_str()).unwrap_or("").to_ascii_lowercase(),
                    "magic4": data.get(..4).map(|x| x.iter().map(|b| format!("{b:02x}")).collect::<String>()).unwrap_or_default(),
                    "starts_rsc7": data.starts_with(b"RSC7"),
                    "starts_rpf7": data.starts_with(b"RPF7"),
                }));
            }
        }
    }
    Ok(())
}

fn inspect_rpf(path: &Path, output: &Path) -> Result<Value, String> {
    let bytes = fs::read(path).map_err(|e| format!("read RPF: {e}"))?;
    let archive = RpfArchive::parse(&bytes, path.file_name().and_then(|x| x.to_str()).unwrap_or("dlc.rpf"), None)
        .map_err(|e| format!("parse RPF: {e:#}"))?;
    let version = format!("{:?}", archive.version);
    let encryption = format!("{:?}", archive.encryption);
    if archive.encryption.is_encrypted() {
        return Ok(json!({
            "file": path.display().to_string(),
            "bytes": bytes.len(),
            "version": version,
            "encryption": encryption,
            "toc_readable": false,
            "declared_entries": archive.entries.len(),
            "extracted_files": 0,
            "warning": "Encrypted RPF: header recognized, TOC cannot be inspected without legitimate keys."
        }));
    }
    let root = archive.entries.first().ok_or("RPF entry table is empty")?;
    let (start, count) = match &root.kind {
        RpfEntryKind::Directory { entries_index, entries_count } => (*entries_index, *entries_count),
        _ => return Err("RPF root entry is not a directory".into()),
    };
    fs::create_dir_all(output).map_err(|e| format!("create output: {e}"))?;
    let mut rows = Vec::new();
    walk_rpf(&archive, &bytes, start, count, "", output, &mut rows)?;
    let mut extensions = std::collections::BTreeMap::<String, usize>::new();
    for row in &rows {
        let ext = row["extension"].as_str().unwrap_or("").to_string();
        *extensions.entry(ext).or_default() += 1;
    }
    Ok(json!({
        "file": path.display().to_string(),
        "bytes": bytes.len(),
        "version": version,
        "encryption": encryption,
        "toc_readable": true,
        "declared_entries": archive.entries.len(),
        "extracted_files": rows.len(),
        "extension_counts": extensions,
        "files": rows
    }))
}

fn inspect_yft(path: &Path) -> Value {
    let result = (|| -> Result<Value, String> {
        let bytes = fs::read(path).map_err(|e| format!("read YFT: {e}"))?;
        let kind = rage_formats::DrawableKind::from_extension("yft").ok_or("YFT parser kind unavailable")?;
        let drawables = rage_formats::parse_drawables(&bytes, kind).map_err(|e| format!("parse YFT: {e:#}"))?;
        let lods: usize = drawables.iter().map(|d| d.drawable.lods.len()).sum();
        let models: usize = drawables.iter().flat_map(|d| &d.drawable.lods).map(|l| l.models.len()).sum();
        let geometries: usize = drawables.iter().flat_map(|d| &d.drawable.lods)
            .flat_map(|l| &l.models).map(|m| m.geometries.len()).sum();
        Ok(json!({"file":path.display().to_string(),"bytes":bytes.len(),"parse":"success",
            "drawable_entries":drawables.len(),"lods":lods,"models":models,"geometries":geometries}))
    })();
    result.unwrap_or_else(|e| json!({"file":path.display().to_string(),"parse":"failed","error":e}))
}

fn inspect_ytd(path: &Path) -> Value {
    let result = (|| -> Result<Value, String> {
        let bytes = fs::read(path).map_err(|e| format!("read YTD: {e}"))?;
        let textures = rage_formats::parse_ytd(&bytes).map_err(|e| format!("parse YTD: {e:#}"))?;
        let details = textures.iter().map(|t| json!({
            "name":t.name,"width":t.width,"height":t.height,"format":t.format.to_string(),
            "mip_levels":t.levels,"pixel_bytes":t.pixel_data.len()
        })).collect::<Vec<_>>();
        Ok(json!({"file":path.display().to_string(),"bytes":bytes.len(),"parse":"success",
            "texture_count":textures.len(),"textures":details}))
    })();
    result.unwrap_or_else(|e| json!({"file":path.display().to_string(),"parse":"failed","error":e}))
}

fn export_ytd_dds(path: &Path, output: &Path) -> Result<Value, String> {
    let bytes = fs::read(path).map_err(|e| format!("read YTD for DDS export: {e}"))?;
    let textures = rage_formats::parse_ytd(&bytes).map_err(|e| format!("parse YTD for DDS export: {e:#}"))?;
    fs::create_dir_all(output).map_err(|e| format!("create DDS output: {e}"))?;
    let mut files = Vec::new();
    let mut names = std::collections::HashSet::new();
    for (index, texture) in textures.iter().enumerate() {
        let dds = texture.to_dds();
        if dds.len() < 128 || !dds.starts_with(b"DDS ") {
            return Err(format!("Texture {} produced an invalid DDS header", texture.name));
        }
        let mut stem: String = texture.name.chars()
            .map(|ch| if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' { ch } else { '_' })
            .collect();
        if stem.is_empty() { stem = format!("texture_{index}"); }
        if stem.len() > 70 { stem.truncate(70); }
        let mut filename = format!("{stem}.dds");
        if !names.insert(filename.to_ascii_lowercase()) {
            filename = format!("{stem}_{index}.dds");
            names.insert(filename.to_ascii_lowercase());
        }
        fs::write(output.join(&filename), &dds).map_err(|e| format!("write DDS {filename}: {e}"))?;
        files.push(json!({"name":filename,"bytes":dds.len(),"source_name":texture.name,
            "width":texture.width,"height":texture.height,"format":texture.format.to_string()}));
    }
    Ok(json!({"ok":true,"source_ytd":path.display().to_string(),"texture_count":textures.len(),
        "exported_dds":files.len(),"output":output.display().to_string(),"files":files}))
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 7 {
        eprintln!("usage: inspect_reference <camry-dlc.rpf> <rpf-output-dir> <camry.yft> <camry.ytd> <dds-output-dir> <report.json>");
        std::process::exit(2);
    }
    let rpf = PathBuf::from(&args[1]);
    let extracted = PathBuf::from(&args[2]);
    let yft = PathBuf::from(&args[3]);
    let ytd = PathBuf::from(&args[4]);
    let dds_output = PathBuf::from(&args[5]);
    let report_path = PathBuf::from(&args[6]);
    let rpf_report = inspect_rpf(&rpf, &extracted).unwrap_or_else(|e| json!({"parse":"failed","error":e}));
    let report = json!({
        "camry_converted_rpf": rpf_report,
        "camry_original_yft": inspect_yft(&yft),
        "camry_original_ytd": inspect_ytd(&ytd),
        "camry_ytd_dds_export": export_ytd_dds(&ytd, &dds_output).unwrap_or_else(|e| json!({"ok":false,"error":e})),
        "interpretation": "Container parse success is not proof of PS4 game compatibility. Compare extracted resource extensions and parse results."
    });
    if let Some(parent) = report_path.parent() { let _ = fs::create_dir_all(parent); }
    fs::write(&report_path, serde_json::to_vec_pretty(&report).unwrap()).expect("write report");
    println!("{}", serde_json::to_string_pretty(&report).unwrap());
}
