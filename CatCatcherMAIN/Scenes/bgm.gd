extends AudioStreamPlayer

## 全游戏背景音乐。做成 autoload 而不是塞进某个场景：标题页 → 棋盘是 change_scene_to_file，
## 播放器跟着场景一起没了，音乐会被硬切成"从头再来"。放在 autoload 就一直不断。
## 循环由 bgm_rest.mp3.import 的 loop=true 决定，这里不管循环。
const TRACK := preload("res://CatCatcherMAIN/Audio/bgm_rest.mp3")


func _ready() -> void:
	stream = TRACK
	volume_db = float(Level.load_config().get("audio", {}).get("music_db", -12))
	play()
