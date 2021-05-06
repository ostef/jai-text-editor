Config :: struct
{
	// Colors
	window_caption_background_color      := NOT_QUITE_BLACK;
	tab_background_color                 := NOT_QUITE_BLACK;
	tab_caption_background_color         := NOT_QUITE_BLACK;
	tab_caption_inactive_background_color := NOT_QUITE_BLACK;
	inactive_background_color            := Vec4.{ 0.2, 0.2, 0.2, 1 };
	inactive_stripes_color               := DARK_GRAY;
	bottom_io_background_color           := NOT_QUITE_BLACK;
	bottom_io_text_color                 := NOT_QUITE_WHITE;
	view_separation_color                := LIGHT_GRAY;
	buffer_background_color              := NOT_QUITE_BLACK;
	buffer_text_color                    := NOT_QUITE_WHITE;
	buffer_line_numbers_text_color       := LIGHT_GRAY;
	buffer_line_numbers_separation_color := LIGHT_GRAY;
	buffer_info_background_color         := LIGHT_GRAY;
	buffer_info_text_color               := VERY_DARK_GRAY;
	text_input_selection_color           := Vec4.{ 0.3, 0.5, 0.9, 0.7 };
	inactive_text_input_selection_color  := Vec4.{ 0.5, 0.5, 0.5, 0.5 };

	// Visuals
	font : string;	// @Note (stefan): Don't give it a default value, because when we'll try to free it, it will crash!
	bottom_io_padding           := 0.0;
	buffer_line_numbers_padding := 0.0;
	buffer_info_padding         := 0.0;
	visual_scrolling_smoothing  := 0.7;		// @Todo (stefan): Make sure this is between 0 and 1
	buffer_render_whitespace := true;
	buffer_rendered_whitespace_dimming := 0.8;
	bottom_io_font_height : u32 = 16;
	buffer_font_height : u32 = 16;
	buffer_info_font_height : u32 = 16;

	word_skipping_stops_at_word_separators := true;
	buffer_show_scrollbar := true;

	// Key bindings
	key_toggle_command_input := Key_Binding.{ Mods.NONE, .ESCAPE };
	key_previous_tab  := Key_Binding.{ Mods.CONTROL | .SHIFT, .W };
	key_next_tab      := Key_Binding.{ Mods.CONTROL | .SHIFT, .E };
	key_previous_view := Key_Binding.{ Mods.CONTROL, .W };
	key_next_view     := Key_Binding.{ Mods.CONTROL, .E };
	key_close_view    := Key_Binding.{ Mods.CONTROL, .Q };
	
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

	key_move_line_up   := Key_Binding.{ Mods.ALT, .UP };
	key_move_line_down := Key_Binding.{ Mods.ALT, .DOWN };

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
	file_contents, ok := read_entire_file (filename, temp_allocator, null_terminate = false);
	if !ok then return false;
	free (config.font, heap_allocator);

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

	font_filename := join (temp_allocator, "fonts/", config.font);
	if loaded_font.filename != font_filename then try_reloading_font (*loaded_font, font_filename);

	return true;
}
