#!/usr/bin/env python3
"""把 Tingye/ 下的新 Swift 文件加入 Tingye app target（不重建整个工程）。
用法：python3 scripts/add-swift-file.py NewFile.swift [...]"""
import sys, re, secrets, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
pbx = root / "Tingye.xcodeproj" / "project.pbxproj"
s = pbx.read_text()
anchor = "DailyQuoteCard.swift"  # 同组、同 target 的参照文件
ref_id = re.search(r"(\w{24}) /\* %s \*/ = \{isa = PBXFileReference" % re.escape(anchor), s).group(1)
build_id = re.search(r"(\w{24}) /\* %s in Sources \*/ = \{isa = PBXBuildFile" % re.escape(anchor), s).group(1)
for name in sys.argv[1:]:
    if f"path = {name};" in s:
        print("already present:", name); continue
    assert (root / "Tingye" / name).exists(), name
    fid, bid = secrets.token_hex(12).upper(), secrets.token_hex(12).upper()
    s = s.replace(f"\t\t{build_id} /* {anchor} in Sources */ = {{isa = PBXBuildFile;",
                  f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};\n\t\t{build_id} /* {anchor} in Sources */ = {{isa = PBXBuildFile;", 1)
    s = s.replace(f"\t\t{ref_id} /* {anchor} */ = {{isa = PBXFileReference;",
                  f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};\n\t\t{ref_id} /* {anchor} */ = {{isa = PBXFileReference;", 1)
    s = s.replace(f"\t\t\t\t{ref_id} /* {anchor} */,", f"\t\t\t\t{ref_id} /* {anchor} */,\n\t\t\t\t{fid} /* {name} */,", 1)
    s = s.replace(f"\t\t\t\t{build_id} /* {anchor} in Sources */,", f"\t\t\t\t{build_id} /* {anchor} in Sources */,\n\t\t\t\t{bid} /* {name} in Sources */,", 1)
    print("added:", name)
pbx.write_text(s)
