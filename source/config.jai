Config :: struct
{
	// Colors
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

	// Visuals
	bottom_io_padding           := 0.0;
	buffer_line_numbers_padding := 0.0;
	buffer_info_padding         := 0.0;
	visual_scrolling_smoothing  := 0.7;		// @Todo (stefan): Make sure this is between 0 and 1

	// Key bindings
	key_toggle_command_input := Key_Binding.{ Mods.NONE, .ESCAPE };
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
	key_move_left  := Key_Binding.{ Mods.NONE, .LEFT };
	key_move_right := Key_Binding.{ Mods.NONE, .RIGHT };

	key_select_up    := Key_Binding.{ Mods.SHIFT, .UP };
	key_select_down  := Key_Binding.{ Mods.SHIFT, .DOWN };
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

// @Todo (stefan): Verify at compile time that the config.edit file does not have
// entries that our Config struct does not.

read_config_from_file :: (filename := "config.edit") -> bool
{
	file_contents, ok := read_entire_file (filename, temp_allocator, null_terminate = false);
	if !ok then return false;

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

	return true;
}
