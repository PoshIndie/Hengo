@tool
extends EditorPlugin

# imports
const _Assets = preload('res://addons/hengo/scripts/assets.gd')
const _Global = preload('res://addons/hengo/scripts/global.gd')
const _SaveLoad = preload('res://addons/hengo/scripts/save_load.gd')
const _Enums = preload('res://addons/hengo/references/enums.gd')

const PLUGIN_NAME = 'Hengo'
const MENU_NATIVE_API_NAME = "Hengo Generate Native Api"

var main_scene
var side_bar
var tabs_hide_helper
var tabs_container

# docks
#
var dock_container
# left docks
var dock_left_1
var dock_left_2
# right docks
var dock_right_1
var dock_right_2
# scene tabs
var scene_tabs
var docks_references: Array = []

# file system tree
var file_system_tree: Tree
var file_tree_signals: Array = []

var debug_plugin: EditorDebuggerPlugin

func _enter_tree():
	debug_plugin = load('res://addons/hengo/scripts/debug/debug_plugin.gd').new()
	add_debugger_plugin(debug_plugin)

	# getting native api like String, float... methods.
	var native_api_file: FileAccess = FileAccess.open(_Enums.NATIVE_API_PATH, FileAccess.READ)
	_Enums.NATIVE_API_LIST = JSON.parse_string(native_api_file.get_as_text())
	native_api_file.close()

	# creating hengo folder
	if not DirAccess.dir_exists_absolute('res://hengo'):
		DirAccess.make_dir_absolute('res://hengo')

		get_editor_interface().get_resource_filesystem().scan()

	# ---------------------------------------------------------------------------- #

	var file_system_dock: EditorFileSystem = EditorInterface.get_resource_filesystem()
	file_system_tree = EditorInterface.get_file_system_dock() \
		.find_child('*SplitContainer*', true, false) \
		.get_child(0)

	file_system_dock.filesystem_changed.connect(
		func() -> void:
			# start with 'res://' item in tree
			var current: TreeItem = file_system_tree.get_root().get_child(1)

			# searching hengo folder item in tree
			for item: TreeItem in current.get_children():
				if item.get_metadata(0) == 'res://hengo/':
					current = item
					break

			# changing icons on hengo files
			while current:
				for item: TreeItem in current.get_children():
					if item.get_metadata(0).ends_with('.gd'):
						# TODO set icon based on script iherit
						item.set_icon(0, load('res://icon.svg'))
				
				current = current.get_next_in_tree()
	)

	# ---------------------------------------------------------------------------- #

	# removing native file system tree signal because I want my signal to trigger first
	for signal_config: Dictionary in file_system_tree.get_signal_connection_list('item_activated'):
		file_tree_signals.append(signal_config)
		file_system_tree.disconnect('item_activated', signal_config.callable)

	# rewriting file system tree item activated signal
	file_system_tree.item_activated.connect(_on_file_tree_item_activated)

	# ---------------------------------------------------------------------------- #

	# setting scene reference here to prevent crash on development when reload scripts on editor :)
	_Assets.ConnectionLineScene = load('res://addons/hengo/scenes/connection_line.tscn')
	_Assets.StateConnectionLineScene = load('res://addons/hengo/scenes/state_connection_line.tscn')
	_Assets.FlowConnectionLineScene = load('res://addons/hengo/scenes/flow_connection_line.tscn')
	_Assets.HengoRootScene = load('res://addons/hengo/scenes/hengo_root.tscn')
	_Assets.CNodeInputScene = load('res://addons/hengo/scenes/cnode_input.tscn')
	_Assets.CNodeOutputScene = load('res://addons/hengo/scenes/cnode_output.tscn')
	_Assets.CNodeScene = load('res://addons/hengo/scenes/cnode.tscn')
	_Assets.CNodeFlowScene = load('res://addons/hengo/scenes/cnode_flow.tscn')
	_Assets.CNodeIfFlowScene = load('res://addons/hengo/scenes/cnode_if_flow.tscn')
	_Assets.EventScene = load('res://addons/hengo/scenes/event.tscn')
	_Assets.EventStructScene = load('res://addons/hengo/scenes/event_structure.tscn')
	_Assets.SideBarSectionItemScene = load('res://addons/hengo/scenes/side_bar_section_item.tscn')
	_Assets.PropContainerScene = load('res://addons/hengo/scenes/prop_container.tscn')
	_Assets.CNodeInputLabel = load('res://addons/hengo/scenes/cnode_input_label.tscn')
	_Assets.CNodeCenterImage = load('res://addons/hengo/scenes/cnode_center_image.tscn')

	_Global.editor_interface = get_editor_interface()
	print('setted')

	main_scene = _Assets.HengoRootScene.instantiate()
	side_bar = load('res://addons/hengo/scenes/side_bar.tscn').instantiate()

	_Global.SIDE_MENU_POPUP = main_scene.get_node('%SideMenuPopUp')
	_Global.GENERAL_POPUP = main_scene.get_node('%GeneralPopUp')

	EditorInterface.get_editor_main_screen().add_child(main_scene)
	_make_visible(false)

	var root = get_node('/root')

	# setting tabs references
	dock_container = root.find_child('DockHSplitLeftL', true, false)
	dock_left_1 = dock_container.find_child('DockVSplitLeftL', true, false)
	dock_left_2 = dock_container.find_child('DockVSplitLeftR', true, false)
	dock_right_1 = dock_container.find_child('DockVSplitRightL', true, false)
	dock_right_2 = dock_container.find_child('DockVSplitRightR', true, false)
	scene_tabs = get_editor_interface().get_editor_main_screen().get_node('../..').get_child(0)
	
	add_tool_menu_item(MENU_NATIVE_API_NAME, _generate_native_api)

	main_screen_changed.connect(_on_change_main_screen)
	set_docks()

	add_autoload_singleton('HengoDebugger', 'res://addons/hengo/scripts/debug/hengo_debugger.gd')
	_Global.HENGO_EDITOR_PLUGIN = self

func _generate_native_api() -> void:
	var file: FileAccess = FileAccess.open('res://.api/extension_api.json', FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())

	var native_api: Dictionary = {}

	for dict: Dictionary in (data['builtin_classes'] as Array):
		if _Enums.VARIANT_TYPES.has(dict.name):
			if dict.has('methods'):
				var arr: Array = []
				
				for method: Dictionary in dict['methods']:
					var dt: Dictionary = {
						name = method.name,
						sub_type = 'func',
						inputs = [ {
							name = dict.name,
							type = dict.name,
							ref = true
						}]
					}

					if method.has('arguments'):
						dt.inputs += method.arguments
					
					if method.has('return_type'):
						dt['outputs'] = [ {
							name = '',
							type = method.return_type
						}]

					arr.append({
						name = method.name,
						data = dt
					})
				
				native_api[dict.name] = arr

	var file_json: FileAccess = FileAccess.open(_Enums.NATIVE_API_PATH, FileAccess.WRITE)

	file_json.store_string(
		JSON.stringify(native_api)
	)

	file_json.close()

	print('HENGO NATIVE API GENERATED!!')

	# for d in native_api:
	# 	print(native_api[d])

func _on_file_tree_item_activated() -> void:
	var item: TreeItem = file_system_tree.get_selected()
	var path: StringName = item.get_metadata(0)

	if path.begins_with('res://hengo/') and path.ends_with('.gd'):
		_SaveLoad.load_and_edit(path)
	else:
		for signal_config: Dictionary in file_tree_signals:
			(signal_config.callable as Callable).call()

func _get_window_layout(configuration: ConfigFile) -> void:
	if main_scene.visible:
		hide_docks()
	else:
		set_docks()

func _on_change_main_screen(_name: String) -> void:
	if _name == PLUGIN_NAME:
		hide_docks()
	else:
		show_docks()

func _exit_tree():
	remove_debugger_plugin(debug_plugin)
	remove_tool_menu_item(MENU_NATIVE_API_NAME)

	# reseting file system tree signals
	for signal_config: Dictionary in file_tree_signals:
		file_system_tree.connect('item_activated', signal_config.callable)

	if main_scene:
		main_scene.queue_free()
	
	remove_autoload_singleton('HengoDebugger')
	_Global.HENGO_EDITOR_PLUGIN = null

func _make_visible(_visible: bool):
	if main_scene:
		if _visible: hide_docks()
		else: show_docks()

		main_scene.visible = _visible

func _get_plugin_name():
	return PLUGIN_NAME

func _has_main_screen() -> bool:
	return true

# public
#
func set_docks() -> void:
	docks_references = []

	# hiding left docks
	for dock in dock_left_1.get_children():
		docks_references.append({
			dock = dock,
			old_visibility = dock.visible
		})

	for dock in dock_left_2.get_children():
		docks_references.append({
			dock = dock,
			old_visibility = dock.visible
		})

	# hiding right docks
	for dock in dock_right_1.get_children():
		docks_references.append({
			dock = dock,
			old_visibility = dock.visible
		})
	
	for dock in dock_right_2.get_children():
		docks_references.append({
			dock = dock,
			old_visibility = dock.visible
		})
	
	print('set layout: ', docks_references)

func hide_docks() -> void:
	scene_tabs.visible = false

	# hiding all docks
	for obj in docks_references:
		obj.dock.visible = false

func show_docks() -> void:
	if scene_tabs:
		scene_tabs.visible = true

	# backuping docks visibility
	for obj in docks_references:
		obj.dock.visible = obj.old_visibility