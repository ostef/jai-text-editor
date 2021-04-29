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
			else
			{
				log_error ("Config", "Unhandled type for member '%'.", member.name);
			}
		}
	}

	return true;
}
