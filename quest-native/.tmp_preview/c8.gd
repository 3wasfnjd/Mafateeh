extends SceneTree
var d; var lv; var won := false; var f := 0
func _initialize():
	Engine.time_scale = 4.0
	d = Diorama.new(); root.add_child(d); d.setup(8)
	lv = TableBarterLevel.new(); d.stage.add_child(lv); lv.setup(d)
	lv.level_won.connect(func(): won = true)
	print("route: ", lv.route())
	lv._visit(2)   # wrong stall first: should be refused
func _process(dt):
	f += 1
	if f == 600: print("after wrong stall: holding=", lv.holding); lv.demo()
	if won: print("WON holding=", lv.holding); return true
	return f > 40000
