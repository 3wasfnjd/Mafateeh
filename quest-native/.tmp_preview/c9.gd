extends SceneTree
var d; var lv; var won := false; var f := 0
func _initialize():
	Engine.time_scale = 4.0
	d = Diorama.new(); root.add_child(d); d.setup(9)
	lv = TableSaniaLevel.new(); d.stage.add_child(lv); lv.setup(d)
	lv.level_won.connect(func(): won = true)
	lv.demo(); print("taps: ", lv._demo.size(), " wet at start: ", lv._wet.size())
func _process(dt):
	f += 1
	if won: print("WON wet=", lv._wet.size()); return true
	return f > 40000
