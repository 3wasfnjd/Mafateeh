extends SceneTree
var d; var lv; var won := false; var f := 0
func _initialize():
	Engine.time_scale = 4.0
	d = Diorama.new(); root.add_child(d); d.setup(6)
	lv = TableDrumLevel.new(); d.stage.add_child(lv); lv.setup(d)
	lv.level_won.connect(func(): won = true)
	print("phrases: ", lv.phrases); lv.demo()
func _process(dt):
	f += 1
	if won: print("WON turn=", lv.turn); return true
	return f > 40000
