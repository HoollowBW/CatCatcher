extends SceneTree

## 字体子集化工具（仅支持 glyf 轮廓的 TrueType）。
##
## 为什么要它：项目要中文，但霞鹜文楷 6.97 MB + 得意黑 2.05 MB 会被整份打进 pck
## （Godot 的动态字体只按需栅格化，**源文件还是整份随包发**）。这里把字体裁成
## "屏幕上真会出现的字符"，体积从 9 MB 掉到几百 KB。
##
## 用法（改过中文文案后重跑一遍，然后重新 --import）：
##   godot --headless --path . --script res://tools/subset_font.gd -- \
##       res://CatCatcherMAIN/Fonts/DeYiHei/SmileySans-Oblique-2.ttf \
##       res://CatCatcherMAIN/Fonts/subset/display.ttf
##
## 步骤：解析 sfnt 目录 -> 从 cmap 取需要的字符（含复合字形的递归闭包）->
## 重排 glyf/loca/hmtx/maxp/hhea/head/post/cmap，其余大表（GSUB/GPOS/GDEF/kern…）丢掉。
##
## ⚠️ Godot 的 PackedByteArray.decode_*/encode_* 是**小端**，而 TTF 全是大端，
##    所以下面所有多字节读写都手写，不要图省事用 decode_u16 那一套。

const SRC_DIRS := ["res://CatCatcherMAIN"]

var _src := PackedByteArray()
var _tables := {}            # tag -> [offset, length]
var _glyphs := []            # 新 gid -> PackedByteArray
var _old_to_new := {}        # 旧 gid -> 新 gid
var _adv := []               # 新 gid -> advance width
var _lsb := []               # 新 gid -> left side bearing
var _char_map := {}          # codepoint -> 旧 gid
var _final_char_map := {}    # codepoint -> 新 gid


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("用法: -- <源字体.ttf> <输出.ttf>")
		quit(1)
		return
	var src_path := String(args[0])
	var dst_path := String(args[1])

	if not _load_font(src_path):
		quit(1)
		return
	print("源字体 %s：%d 张表，%d 个字形" % [src_path.get_file(), _tables.size(), _num_glyphs()])

	var chars := _collect_chars()
	var cmap := _read_cmap()
	var missing := []
	var wanted := {}
	for cp in chars:
		if cmap.has(cp):
			wanted[int(cmap[cp])] = true
			_char_map[cp] = int(cmap[cp])
		else:
			missing.append(cp)
	print("需要 %d 个字符，字体里有 %d 个" % [chars.size(), chars.size() - missing.size()])
	if not missing.is_empty():
		var sample := ""
		for i in mini(8, missing.size()):
			sample += String.chr(missing[i])
		print("  （字体缺 %d 个，多半是注释里的少见字：%s…）" % [missing.size(), sample])
	if wanted.is_empty():
		printerr("一个字符都没匹配上，放弃")
		quit(1)
		return

	_build_subset(wanted.keys())
	_write_font(dst_path)
	var size_kb := int(FileAccess.get_file_as_bytes(dst_path).size() / 1024.0)
	print("输出 %s：%d 个字形，%d KB" % [dst_path.get_file(), _glyphs.size(), size_kb])
	_verify(dst_path)
	quit(0)


# ---------------------------------------------------------------- 大端读写 ----

func _u8(o: int) -> int:
	return _src[o]


func _u16(o: int) -> int:
	return (_src[o] << 8) | _src[o + 1]


func _s16(o: int) -> int:
	var v := _u16(o)
	return v - 0x10000 if v >= 0x8000 else v


func _u32(o: int) -> int:
	return (_src[o] << 24) | (_src[o + 1] << 16) | (_src[o + 2] << 8) | _src[o + 3]


func _be_u16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]


func _be_s16(b: PackedByteArray, o: int) -> int:
	var v := _be_u16(b, o)
	return v - 0x10000 if v >= 0x8000 else v


func _put_u16(b: PackedByteArray, o: int, v: int) -> void:
	b[o] = (v >> 8) & 0xFF
	b[o + 1] = v & 0xFF


func _put_u32(b: PackedByteArray, o: int, v: int) -> void:
	b[o] = (v >> 24) & 0xFF
	b[o + 1] = (v >> 16) & 0xFF
	b[o + 2] = (v >> 8) & 0xFF
	b[o + 3] = v & 0xFF


func _pack_u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	_put_u16(b, 0, v & 0xFFFF)
	return b


func _pack_s16(v: int) -> PackedByteArray:
	return _pack_u16(v & 0xFFFF)


func _pack_u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	_put_u32(b, 0, v)
	return b


# ---------------------------------------------------------------- 读源字体 ----

func _load_font(path: String) -> bool:
	_src = FileAccess.get_file_as_bytes(path)
	if _src.size() < 12:
		printerr("读不到字体: " + path)
		return false
	var version := _u32(0)
	if version != 0x00010000 and version != 0x74727565:
		printerr("不是 TrueType(glyf) 字体（sfnt=0x%X），CFF 轮廓不支持" % version)
		return false
	var n := _u16(4)
	_tables.clear()
	for i in n:
		var p := 12 + i * 16
		var tag := ""
		for k in 4:
			tag += String.chr(_src[p + k])
		_tables[tag] = [_u32(p + 8), _u32(p + 12)]
	if not _tables.has("glyf") or not _tables.has("loca"):
		printerr("缺 glyf/loca，不是 TrueType 轮廓")
		return false
	return true


func _table(tag: String) -> int:
	return int(_tables[tag][0])


func _table_len(tag: String) -> int:
	return int(_tables[tag][1])


func _num_glyphs() -> int:
	return _u16(_table("maxp") + 4)


func _num_hmetrics() -> int:
	return _u16(_table("hhea") + 34)


## cmap -> { codepoint: gid }。优先 format 12，其次 format 4。
func _read_cmap() -> Dictionary:
	var out := {}
	var base := _table("cmap")
	var n := _u16(base + 2)
	var best4 := -1
	var best12 := -1
	for i in n:
		var rec := base + 4 + i * 8
		var platform := _u16(rec)
		var off := base + _u32(rec + 4)
		if platform != 3 and platform != 0:
			continue
		var fmt := _u16(off)
		if fmt == 12 and best12 < 0:
			best12 = off
		elif fmt == 4 and best4 < 0:
			best4 = off

	if best12 >= 0:
		var groups := _u32(best12 + 12)
		for g in groups:
			var p := best12 + 16 + g * 12
			var start_cp := _u32(p)
			var end_cp := _u32(p + 4)
			var start_gid := _u32(p + 8)
			for cp in range(start_cp, end_cp + 1):
				out[cp] = start_gid + (cp - start_cp)
		return out

	if best4 >= 0:
		var seg := _u16(best4 + 6) / 2
		var end_base := best4 + 14
		var start_base := end_base + seg * 2 + 2
		var delta_base := start_base + seg * 2
		var range_base := delta_base + seg * 2
		for s in seg:
			var end_cp := _u16(end_base + s * 2)
			var start_cp := _u16(start_base + s * 2)
			var delta := _s16(delta_base + s * 2)
			var range_off := _u16(range_base + s * 2)
			if start_cp == 0xFFFF:
				continue
			for cp in range(start_cp, end_cp + 1):
				var gid := 0
				if range_off == 0:
					gid = (cp + delta) & 0xFFFF
				else:
					var addr := range_base + s * 2 + range_off + (cp - start_cp) * 2
					if addr + 1 < _src.size():
						gid = _u16(addr)
						if gid != 0:
							gid = (gid + delta) & 0xFFFF
				if gid != 0:
					out[cp] = gid
		return out

	printerr("cmap 里没有 format 4/12 子表")
	return out


func _glyph_bytes(gid: int) -> PackedByteArray:
	var long_fmt := _s16(_table("head") + 50) == 1
	var base := _table("loca")
	var a: int
	var b: int
	if long_fmt:
		a = _u32(base + gid * 4)
		b = _u32(base + (gid + 1) * 4)
	else:
		a = _u16(base + gid * 2) * 2
		b = _u16(base + (gid + 1) * 2) * 2
	if b <= a:
		return PackedByteArray()
	var glyf := _table("glyf")
	return _src.slice(glyf + a, glyf + b)


## 复合字形引用的子字形编号（简单字形返回空）。
func _components(data: PackedByteArray) -> Array:
	var out := []
	if data.size() < 10 or _be_s16(data, 0) >= 0:
		return out
	var p := 10
	while p + 4 <= data.size():
		var flags := _be_u16(data, p)
		out.append(_be_u16(data, p + 2))
		p += 4
		p += 4 if (flags & 0x0001) != 0 else 2          # ARG_1_AND_2_ARE_WORDS
		if (flags & 0x0008) != 0:
			p += 2
		elif (flags & 0x0040) != 0:
			p += 4
		elif (flags & 0x0080) != 0:
			p += 8
		if (flags & 0x0020) == 0:                       # MORE_COMPONENTS
			break
	return out


# ---------------------------------------------------------------- 建子集 ----

func _build_subset(start_gids: Array) -> void:
	# 1) 闭包：复合字形引用的子字形也要带上，不然渲染出来缺块
	var need := {}
	need[0] = true
	var queue := start_gids.duplicate()
	while not queue.is_empty():
		var gid := int(queue.pop_back())
		if need.has(gid):
			continue
		need[gid] = true
		for c in _components(_glyph_bytes(gid)):
			if not need.has(int(c)):
				queue.append(int(c))

	# 2) 排新 gid：0 恒为 .notdef，其余按旧 gid 升序（结果确定）
	var olds := need.keys()
	olds.sort()
	_old_to_new.clear()
	_glyphs.clear()
	_adv.clear()
	_lsb.clear()
	var hmetrics := _num_hmetrics()
	var hmtx := _table("hmtx")
	var last_adv := 0
	if hmetrics > 0:
		last_adv = _u16(hmtx + (hmetrics - 1) * 4)
	for newg in olds.size():
		var oldg := int(olds[newg])
		_old_to_new[oldg] = newg
		var data := _glyph_bytes(oldg)
		if not data.is_empty() and _be_s16(data, 0) < 0:
			data = _patch_components(data)
		_glyphs.append(data)
		if oldg < hmetrics:
			_adv.append(_u16(hmtx + oldg * 4))
			_lsb.append(_s16(hmtx + oldg * 4 + 2))
		else:
			_adv.append(last_adv)
			_lsb.append(_s16(hmtx + hmetrics * 4 + (oldg - hmetrics) * 2))

	# 3) cmap 用：codepoint -> 新 gid
	_final_char_map.clear()
	for cp in _char_map:
		_final_char_map[cp] = int(_old_to_new.get(int(_char_map[cp]), 0))


## 复合字形里的子字形编号要换成新编号。
func _patch_components(data: PackedByteArray) -> PackedByteArray:
	var out := data.duplicate()
	var p := 10
	while p + 4 <= out.size():
		var flags := _be_u16(out, p)
		var oldg := _be_u16(out, p + 2)
		_put_u16(out, p + 2, int(_old_to_new.get(oldg, 0)))
		p += 4
		p += 4 if (flags & 0x0001) != 0 else 2
		if (flags & 0x0008) != 0:
			p += 2
		elif (flags & 0x0040) != 0:
			p += 4
		elif (flags & 0x0080) != 0:
			p += 8
		if (flags & 0x0020) == 0:
			break
	return out


# ---------------------------------------------------------------- 写字体 ----

func _write_font(dst_path: String) -> void:
	# glyf / loca（loca 一定是 numGlyphs+1 个偏移，用 long 格式）
	var glyf := PackedByteArray()
	var loca := PackedByteArray()
	for g in _glyphs.size():
		loca.append_array(_pack_u32(glyf.size()))
		glyf.append_array(_glyphs[g])
		while glyf.size() % 4 != 0:
			glyf.append(0)
	loca.append_array(_pack_u32(glyf.size()))

	# hmtx：全部写成完整条目（numberOfHMetrics = 字形数）
	var hmtx := PackedByteArray()
	for g in _glyphs.size():
		hmtx.append_array(_pack_u16(_adv[g]))
		hmtx.append_array(_pack_s16(_lsb[g]))

	var head := _slice_table("head")
	_put_u32(head, 8, 0)                       # checkSumAdjustment 归零
	_put_u16(head, 50, 1)                      # indexToLocFormat = long
	var hhea := _slice_table("hhea")
	_put_u16(hhea, 34, _glyphs.size())         # numberOfHMetrics
	var maxp := _slice_table("maxp")
	_put_u16(maxp, 4, _glyphs.size())          # numGlyphs

	var post := PackedByteArray()
	post.append_array(_pack_u32(0x00030000))   # version 3.0：不带字形名
	post.append_array(_pack_u32(0))            # italicAngle
	post.append_array(_pack_s16(0))            # underlinePosition
	post.append_array(_pack_s16(0))            # underlineThickness
	post.append_array(_pack_u32(0))            # isFixedPitch
	for i in 4:
		post.append_array(_pack_u32(0))        # 四个 mem 字段

	var out := {
		"head": head, "hhea": hhea, "maxp": maxp,
		"hmtx": hmtx, "loca": loca, "glyf": glyf,
		"post": post, "cmap": _build_cmap(),
	}
	for tag in ["name", "OS/2", "cvt ", "fpgm", "prep", "gasp"]:
		if _tables.has(tag):
			out[tag] = _slice_table(tag)

	var tags := out.keys()
	tags.sort()
	var n := tags.size()
	var pow2 := 1
	var sel := 0
	while pow2 * 2 <= n:
		pow2 *= 2
		sel += 1

	var header := PackedByteArray()
	header.append_array(_pack_u32(0x00010000))
	header.append_array(_pack_u16(n))
	header.append_array(_pack_u16(pow2 * 16))              # searchRange
	header.append_array(_pack_u16(sel))                    # entrySelector
	header.append_array(_pack_u16(n * 16 - pow2 * 16))     # rangeShift

	var dir := PackedByteArray()
	var datas := []
	var offset := 12 + n * 16
	for tag in tags:
		var data: PackedByteArray = out[tag]
		dir.append_array(tag.to_ascii_buffer())
		dir.append_array(_pack_u32(0))                     # checksum（FreeType 不校验）
		dir.append_array(_pack_u32(offset))
		dir.append_array(_pack_u32(data.size()))
		datas.append(data)
		offset += data.size() + (4 - data.size() % 4) % 4

	var file := PackedByteArray()
	file.append_array(header)
	file.append_array(dir)
	for data in datas:
		file.append_array(data)
		while file.size() % 4 != 0:
			file.append(0)

	DirAccess.make_dir_recursive_absolute(dst_path.get_base_dir())
	var f := FileAccess.open(dst_path, FileAccess.WRITE)
	if f == null:
		printerr("写不进: " + dst_path)
		return
	f.store_buffer(file)
	f.close()


func _slice_table(tag: String) -> PackedByteArray:
	var off := _table(tag)
	return _src.slice(off, off + _table_len(tag))


## 只写一张 format 4 子表（BMP 够用）：一个字符一段，简单但正确。
func _build_cmap() -> PackedByteArray:
	var pairs := []
	var cps := _final_char_map.keys()
	cps.sort()
	for cp in cps:
		pairs.append([int(cp), int(_final_char_map[cp])])

	var seg := pairs.size() + 1
	var length := 16 + seg * 8
	var pow2 := 1
	var sel := 0
	while pow2 * 2 <= seg:
		pow2 *= 2
		sel += 1

	var t := PackedByteArray()
	t.append_array(_pack_u16(0))            # version
	t.append_array(_pack_u16(1))            # numTables
	t.append_array(_pack_u16(3))            # platformID = Windows
	t.append_array(_pack_u16(1))            # encodingID = Unicode BMP
	t.append_array(_pack_u32(12))           # 子表偏移

	t.append_array(_pack_u16(4))            # format 4
	t.append_array(_pack_u16(length))
	t.append_array(_pack_u16(0))            # language
	t.append_array(_pack_u16(seg * 2))      # segCountX2
	t.append_array(_pack_u16(pow2 * 2))                     # searchRange
	t.append_array(_pack_u16(sel))                          # entrySelector
	t.append_array(_pack_u16(seg * 2 - pow2 * 2))            # rangeShift

	for pair in pairs:
		t.append_array(_pack_u16(int(pair[0])))
	t.append_array(_pack_u16(0xFFFF))                        # 收尾段
	t.append_array(_pack_u16(0))                             # reservedPad
	for pair in pairs:
		t.append_array(_pack_u16(int(pair[0])))
	t.append_array(_pack_u16(0xFFFF))
	for pair in pairs:
		t.append_array(_pack_u16((int(pair[1]) - int(pair[0])) & 0xFFFF))
	t.append_array(_pack_u16(1))                             # 0xFFFF -> .notdef
	for i in seg:
		t.append_array(_pack_u16(0))                         # idRangeOffset
	return t


# ---------------------------------------------------------------- 字符集 ----

## ASCII 全量 + 源码字符串字面量里的非 ASCII 字符（注释里的不算）。
func _collect_chars() -> Array:
	var set := {}
	for cp in range(0x20, 0x7F):
		set[cp] = true
	var files := []
	for d in SRC_DIRS:
		_walk(d, files)
	for path in files:
		for ch in _string_chars(FileAccess.get_file_as_string(path)):
			var cp := String(ch).unicode_at(0)
			if cp > 0x7E:
				set[cp] = true
	var out := set.keys()
	out.sort()
	return out


func _walk(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := path.path_join(name)
			if dir.current_is_dir():
				_walk(full, out)
			elif name.ends_with(".gd") or name.ends_with(".tscn"):
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _string_chars(text: String) -> Array:
	var out := []
	var in_str := false
	var quote := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if in_str:
			if c == "\\":
				i += 2
				continue
			if c == quote:
				in_str = false
			else:
				out.append(c)
		elif c == "#":
			while i < text.length() and text[i] != "\n":
				i += 1
		elif c == "\"" or c == "'":
			in_str = true
			quote = c
		i += 1
	return out


# ---------------------------------------------------------------- 校验 ----

func _verify(path: String) -> void:
	var font = load(path)
	if font == null:
		printerr("⚠️ 输出字体加载失败")
		return
	var bad := []
	for cp in _final_char_map.keys():
		if not font.has_char(cp):
			bad.append(cp)
	if bad.is_empty():
		print("✓ 校验：%d 个字符全部能取到字形" % _final_char_map.size())
	else:
		printerr("⚠️ %d 个字符取不到字形" % bad.size())
