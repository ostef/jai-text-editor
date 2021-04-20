Text_Input :: struct
{
	Flags :: enum_flags
	{
		SINGLE_LINE;
		DISALLOW_TABS;
	}

	Newline_Policy :: enum
	{
		LF;
		CRLF;
	}

	flags   : Flags;
	newline : Newline_Policy;
	buffer  : Gap_Buffer;
}

text_input_handle_event :: (using input : *Text_Input, event : Event) -> bool
{
	modified := false;
	if event.type ==
	{
	case .KEY_PRESS; #through;
	case .KEY_REPEAT;
		if event.key_event.key_code ==
		{
		case .UP;
			// @Todo (stefan): Handle selection
			if move_cursor_to_previous_line (*buffer) then modified = true;

		case .DOWN;
			// @Todo (stefan): Handle selection
			if move_cursor_to_next_line (*buffer) then modified = true;

		case .LEFT;
			if (event.key_event.mods & .SHIFT)
			{
				if select_backward (*buffer) then modified = true;
			}
			else
			{
				if move_cursor_backward (*buffer) then modified = true;
			}

		case .RIGHT;
			if (event.key_event.mods & .SHIFT)
			{
				if select_forward (*buffer) then modified = true;
			}
			else
			{
				if move_cursor_forward (*buffer) then modified = true;
			}

		case .BACKSPACE;
			if backspace_selection (*buffer) then modified = true;

		case .DELETE;
			if delete_selection (*buffer) then modified = true;

		case .RETURN;
			if (flags & .SINGLE_LINE) != .SINGLE_LINE
			{
				if #complete newline ==
				{
				case .LF;   insert_at_cursor (*buffer, "\n");
				case .CRLF; insert_at_cursor (*buffer, "\r\n");
				}

				modified = true;
			}

		case .TAB;
			if (flags & .DISALLOW_TABS) != .DISALLOW_TABS
			{
				insert_at_cursor (*buffer, "\t");
				modified = true;
			}
		}

	case .TEXT_INPUT;
		if !is_control (event.text_input_event.codepoint)
		{
			insert_at_cursor (*buffer, event.text_input_event.codepoint);
			modified = true;
		}
	}

	return modified;
}

init_text_input :: (input : *Text_Input, flags : Text_Input.Flags)
{
	input.flags = flags;
	init_gap_buffer (*input.buffer, 5000, heap_allocator);
}

reset_text_input :: (using input : *Text_Input)
{
	reset_gap_buffer (*buffer);
}

load_file_into_buffer :: (using input : *Text_Input, filename : string) -> bool
{
	file_contents, ok := read_entire_file (filename, temp_allocator, null_terminate = false);
	if !ok then return false;
	
	clear_gap_buffer (*buffer);
	for i : 0..file_contents.count - 1
		insert_at_cursor (*buffer, file_contents[i]);
	
	// Detect newline policy
	newline = .LF;
	str := utf8 (file_contents);

	// @Speed (stefan): Do this above when populating the gap buffer maybe ?
	// @Todo (stefan): Check for inconsistent line endings.
	for char, i : str
	{
		if char == #char "\r"
		{
			newline = .CRLF;
	
			break;
		}
	}

	return true;
}

write_buffer_to_file :: (using input : *Text_Input, filename : string) -> written : s64, ok : bool
{
	str := clone_to_string (buffer, temp_allocator);
	written, ok := write_to_file (filename, str);

	return written, ok;
}

calculate_drawn_cursor_position :: (using input : *Text_Input, position : Vec2) -> Vec2 #must
{
	cursor_position : Vec2;
	cursor_advance  := default_font.space_advance;

	pen := position;
	pen.y += default_font.ascender;

	for :utf32 codepoint, i : buffer
	{
		glyph := load_glyph (default_font, codepoint);
		if !glyph then continue;
		
		if i == buffer.cursor
		{
			cursor_position = pen;
			cursor_advance  = glyph.advance >> 6;
		}

		if codepoint == #char "\n"
		{
			pen.x = position.x;
			pen.y += (default_font.ascender - default_font.descender);

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += default_font.space_advance;

			while cast (int) (pen.x - position.x) % (default_font.space_advance * 4) != 0
			{
				pen.x += default_font.space_advance;
			}

			// Highlight the whole tab
			if i == buffer.cursor
			{
				cursor_advance = xx (pen.x - cursor_position.x);
			}

			continue;
		}
		
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);
		pen.x += glyph.advance >> 6;
	}
	if buffer.cursor == gap_buffer_count (buffer) then cursor_position = pen;

	return cursor_position;
}

calculate_drawn_text_bounds :: (using input : *Text_Input) -> Vec2 #must
{
	pen := vec2 (0, xx (default_font.ascender - default_font.descender));
	max := pen;
	for :utf32 codepoint, i : buffer
	{
		glyph := load_glyph (default_font, codepoint);
		if !glyph then continue;

		if codepoint == #char "\n"
		{
			pen.x = 0;
			pen.y += (default_font.ascender - default_font.descender);
			if pen.x > max.x then max.x = pen.x;
			if pen.y > max.y then max.y = pen.y;

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += default_font.space_advance;

			while cast (int) pen.x % (default_font.space_advance * 4) != 0
			{
				pen.x += default_font.space_advance;
			}

			if pen.x > max.x then max.x = pen.x;
			if pen.y > max.y then max.y = pen.y;

			continue;
		}
		
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);
		pen.x += glyph.advance >> 6;

		if pen.x > max.x then max.x = pen.x;
		if pen.y > max.y then max.y = pen.y;
	}
	
	return max;
}

draw_text_input :: (using input : *Text_Input, position : Vec2, color : Vec4, clip_rect : Clip_Rect, draw_cursor := true)
{
	cursor_position : Vec2;
	cursor_advance  := default_font.space_advance;

	pen := position;
	pen.y += default_font.ascender;
	immediate_shader (text_spo);

	for :utf32 codepoint, i : buffer
	{
		if pen.y < xx clip_rect.y1 && codepoint != #char "\n" then continue;
		if pen.y > xx clip_rect.y2 then break;
		
		glyph := load_glyph (default_font, codepoint);
		if !glyph then continue;
		
		if i == buffer.cursor
		{
			cursor_position = pen;
			cursor_advance  = glyph.advance >> 6;
		}

		if codepoint == #char "\n"
		{
			pen.x = position.x;
			pen.y += (default_font.ascender - default_font.descender);

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += default_font.space_advance;

			while cast (int) (pen.x - position.x) % (default_font.space_advance * 4) != 0
			{
				pen.x += default_font.space_advance;
			}

			// Highlight the whole tab
			if i == buffer.cursor
			{
				cursor_advance = xx (pen.x - cursor_position.x);
			}

			continue;
		}
		
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);
		immediate_texture (glyph.texture);
		immediate_quad (glyph_position.x, glyph_position.y, glyph_position.x + glyph.bitmap_width, glyph_position.y + glyph.bitmap_height, color);
		immediate_flush ();

		pen.x += glyph.advance >> 6;
	}
	if buffer.cursor == gap_buffer_count (buffer) then cursor_position = pen;

	immediate_texture (0);
	immediate_shader (0);
	
	if draw_cursor
	{
		cursor_alpha := cast (f32) range_map (cos (Basic.get_time () * 5), -1, 1, 0, 1);
		immediate_quad (cursor_position.x, cursor_position.y - default_font.ascender,
			cursor_position.x + cursor_advance, cursor_position.y - default_font.descender, vec4 (1, 1, 1, cursor_alpha));
	}
}
