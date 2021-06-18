Config :: struct
{
	color_theme : string;

	// Visuals
	font : string;	// @Note (stefan): Don't give it a default value, because when we'll try to free it, it will crash!
	visual_cursor_smoothing     := 0.5;
	visual_scrolling_smoothing  := 0.7;		// @Todo (stefan): Make sure this is between 0 and 1
	buffer_render_whitespace := true;
	buffer_rendered_whitespace_dimming := 0.8;
	bottom_io_font_height   : u32 = 16;
	tab_title_font_height   : u32 = 16;
	buffer_font_height      : u32 = 16;
	buffer_info_font_height : u32 = 16;

	word_skipping_stops_at_word_separators := true;

	// Key bindings
	key_toggle_command_input := Key_Binding.{ Mods.NONE, .ESCAPE };
	key_previous_split  := Key_Binding.{ Mods.CONTROL, .W };
	key_next_split      := Key_Binding.{ Mods.CONTROL, .E };
	key_previous_tab := Key_Binding.{ Mods.CONTROL | .SHIFT, .W };
	key_next_tab     := Key_Binding.{ Mods.CONTROL | .SHIFT, .E };

	key_copy  := Key_Binding.{ Mods.CONTROL, .C };
	key_cut   := Key_Binding.{ Mods.CONTROL, .X };
	key_paste := Key_Binding.{ Mods.CONTROL, .V };
	key_undo  := Key_Binding.{ Mods.CONTROL, .Z };
	key_redo  := Key_Binding.{ Mods.CONTROL | .SHIFT, .Z };

	// @Todo (stefan): Unify move and select
	key_move_up    := Key_Binding.{ Mods.NONE, .UP };
	key_move_down  := Key_Binding.{ Mods.NONE, .DOWN };
	key_move_page_up   := Key_Binding.{ Mods.NONE, .PAGE_UP };
	key_move_page_down := Key_Binding.{ Mods.NONE, .PAGE_DOWN };
	key_move_left  := Key_Binding.{ Mods.NONE, .LEFT };
	key_move_right := Key_Binding.{ Mods.NONE, .RIGHT };

	key_select_up    := Key_Binding.{ Mods.SHIFT, .UP };
	key_select_down  := Key_Binding.{ Mods.SHIFT, .DOWN };
	key_select_page_up   := Key_Binding.{ Mods.SHIFT, .PAGE_UP };
	key_select_page_down := Key_Binding.{ Mods.SHIFT, .PAGE_DOWN };
	key_select_left  := Key_Binding.{ Mods.SHIFT, .LEFT };
	key_select_right := Key_Binding.{ Mods.SHIFT, .RIGHT };
	
	key_skip_left         := Key_Binding.{ Mods.CONTROL, .LEFT };
	key_skip_right        := Key_Binding.{ Mods.CONTROL, .RIGHT };
	key_select_skip_left  := Key_Binding.{ Mods.CONTROL | .SHIFT, .LEFT };
	key_select_skip_right := Key_Binding.{ Mods.CONTROL | .SHIFT, .RIGHT };

	key_move_selection_up   := Key_Binding.{ Mods.ALT, .UP };
	key_move_selection_down := Key_Binding.{ Mods.ALT, .DOWN };

	key_scroll_up   := Key_Binding.{ Mods.CONTROL, .UP };
	key_scroll_down := Key_Binding.{ Mods.CONTROL, .DOWN };
	key_scroll_page_up   := Key_Binding.{ Mods.CONTROL, .PAGE_UP };
	key_scroll_page_down := Key_Binding.{ Mods.CONTROL, .PAGE_DOWN };

	key_select_all := Key_Binding.{ Mods.CONTROL, .A };
}

Key_Binding :: struct
{
	mods : Mods;
	key  : Key_Code;
}

color_theme : Map (string, Vec4);

matches_key_binding :: (event : Event, binding : Key_Binding) -> bool #must
{
	return event.key_event.key_code == binding.key && event.key_event.mods == binding.mods;
}

parse_key_binding :: (str : string, allow_no_mods := true) -> Key_Binding #must, ok : bool
{
	if str.count == 0 then return Key_Binding.{}, false;

	result : Key_Binding;
	parts := break_by (str, "+", temp_allocator);
	for parts
	{
		if it ==
		{
		case "CTRL";  result.mods |= .CONTROL;
		case "SHIFT"; result.mods |= .SHIFT;
		case "ALT";   result.mods |= .ALT;
		case;         result.key = enum_value (Key_Code, it);
		}
	}

	if !allow_no_mods && result.mods == .NONE then return Key_Binding.{}, false;

	return result, true;
}

config : Config;

read_config_from_file :: (filename := "config.edit") -> bool
{
	full_path := make_path (temp_allocator, executable_dir, "/", filename);
	file_contents, ok := read_entire_file (full_path, temp_allocator, null_terminate = false);
	if !ok then return false;
	free (config.font, heap_allocator);
	free (config.color_theme, heap_allocator);

	lines := break_by_lines (file_contents, temp_allocator);
	for * lines
	{
		<<it = skip_spaces (<<it);
	}

	config_info := cast (*Type_Info_Struct) type_info (Config);
	for member : config_info.members
	{
		line : string;
		for current_line : lines
		{
			if current_line[0] == #char "#" then continue;
			if starts_with_word (current_line, member.name)
			{
				line = current_line;
			
				break;
			}
		}

		if line
		{
			line = advance (line, member.name.count);
			line = skip_spaces (line);
			
			// @Cleanup
			if member.type == type_info (f32)
			{
				value, ok := string_to_f32 (line);
				if !ok
				{
					log_error ("Config", "Could not read member '%'.", member.name);

					continue member;
				}

				memcpy (cast (*u8) *config + member.offset_in_bytes, *value, member.type.runtime_size);
			}
			else if member.type == type_info (u32)
			{
				value, ok := string_to_u64 (line);
				if !ok
				{
					log_error ("Config", "Could not read member '%'.", member.name);

					continue member;
				}
				value32 := cast (u32) value;

				memcpy (cast (*u8) *config + member.offset_in_bytes, *value32, member.type.runtime_size);
			}
			else if member.type == type_info (bool)
			{
				value, ok := string_to_bool (line);
				if !ok
				{
					log_error ("Config", "Could not read member '%'.", member.name);

					continue member;
				}

				memcpy (cast (*u8) *config + member.offset_in_bytes, *value, member.type.runtime_size);
			}
			else if member.type == type_info (string)
			{
				quoted := line[0] == #char "\"";
				if quoted then line = advance (line);
				i := 0;
				while i < line.count
				{
					if line[i] == #char "\"" then break;
					i += 1;
				}
				if quoted && line[i] != #char "\"" then continue member;
				if quoted then i -= 1;
				line.count = i + 1;
				str := clone_string (line, heap_allocator);
				memcpy (cast (*u8) *config + member.offset_in_bytes, *str, member.type.runtime_size);
			}
			else if member.type == type_info (Vec4)
			{
				value : Vec4;
				ok : bool;
				value.x, ok, line = string_to_f32 (line);
				if !ok
				{
					log_error ("Config", "Could not read member '%'.", member.name);

					continue member;
				}
				
				line = skip_spaces (line);
				value.y, ok, line = string_to_f32 (line);
				if !ok
				{
					log_error ("Config", "Could not read member '%'.", member.name);

					continue member;
				}

				line = skip_spaces (line);
				value.z, ok, line = string_to_f32 (line);
				if !ok
				{
					log_error ("Config", "Could not read member '%'.", member.name);

					continue member;
				}

				line = skip_spaces (line);
				value.w, ok, line = string_to_f32 (line);
				if !ok
				{
					log_error ("Config", "Could not read member '%'.", member.name);

					continue member;
				}
				
				memcpy (cast (*u8) *config + member.offset_in_bytes, *value, member.type.runtime_size);
			}
			else if member.type == type_info (Key_Binding)
			{
				value, ok := parse_key_binding (line);
				if !ok
				{
					log_error ("Config", "Could not read key_binding member '%'.", member.name);

					continue member;
				}

				memcpy (cast (*u8) *config + member.offset_in_bytes, *value, member.type.runtime_size);
			}
			else
			{
				log_error ("Config", "Unhandled type for member '%'.", member.name);
			}
		}
	}

	font_filename := make_path (temp_allocator, executable_dir, "/fonts/", config.font);
	if loaded_font.filename != font_filename then try_reloading_font (*loaded_font, font_filename);
	if !read_color_theme (config.color_theme) then log_error ("Config", "Could not read color theme.");

	return true;
}

read_color_theme :: (theme_name : string) -> bool
{
	filename := make_path (temp_allocator, executable_dir, "/themes/", theme_name, ".edit");
	file_contents, ok := read_entire_file (filename, temp_allocator);
	if !ok then return false;
	
	lines := break_by_lines (file_contents, temp_allocator);
	for * lines
	{
		<<it = trim_spaces_at_ends (<<it);
	}
	
	// Clear the color theme map
	for val, key : color_theme
		free (key, heap_allocator);
	clear_map (*color_theme);
	
	for lines
	{
		line := it;
		if line[0] == #char "#" then continue;
		name := line;
		name.count = 0;
		while line.count > 0 && line[0] != #char " "
		{
			name.count += 1;
			line.data  += 1;
			line.count -= 1;
		}
		line = skip_spaces (line);
		color := line;
		if color.count != 0 && color[0] != #char "#"
		{
			log_error ("Color_Theme", "Invalid line %. Color value should start with a '#'", it_index + 1);
		
			continue;
		}
		color = advance (color);
		r, g, b, a : u8;
		// RGB
		if color.count == 6
		{
			rstr := trim (color, 4);
			gstr := trim (advance (color, 2), 2);
			bstr := advance (color, 4);
			r = cast (u8) string_to_u64 (rstr, 16);
			g = cast (u8) string_to_u64 (gstr, 16);
			b = cast (u8) string_to_u64 (bstr, 16);
			a = 255;
		}
		// RGBA
		else if color.count == 8
		{
			rstr := trim (color, 6);
			gstr := trim (advance (color, 2), 4);
			bstr := trim (advance (color, 4), 2);
			astr := advance (color, 6);
			r = cast (u8) string_to_u64 (rstr, 16);
			g = cast (u8) string_to_u64 (gstr, 16);
			b = cast (u8) string_to_u64 (bstr, 16);
			a = cast (u8) string_to_u64 (astr, 16);
		}
		// Invalid
		else
		{
			log_error ("Color_Theme", "Invalid color at line %.", it_index + 1);
			
			continue;
		}
		
		value := vec4 (r / 255.0, g / 255.0, b / 255.0, a / 255.0);
		insert_to_map (*color_theme, clone_string (name, heap_allocator), value);
	}
	
	return true;
}

get_color_from_theme :: (name : string, secondary_name := "", default_value := NOT_QUITE_WHITE) -> Vec4 #must
{
	if secondary_name
	{
		result, ok := get_value (color_theme, secondary_name, default_value);
		if ok then return result;
	}
	
	return get_value (color_theme, name, default_value);
}