#scope_file
INIT_WITH_FILE :: true;
FILEPATH       :: "out.txt";
OUTPUT_FILE    :: "out.txt";
#scope_export

/*
 * I just monitored how many calls to the expensive procedures (when I say expensive,
 * I mean the procedures that loop over the whole buffer). At most, 2 calls are made to get_text_area_cursor_position.
 * The other procedures (get_line_count, get_wrapped_line_count and scroll_text_area_to_cursor)
 * are called only once when writing to the buffer. That's it. So what I wrote before, not being actually based on any
 * evidence, is false. When we'll have more complicated writing mechanisms such as multiple cursor eventually, this might
 * not be true anymore !
 *																		ostef, November 29 2020
 */

TEXT_VIEW_SCROLL_MARGIN    :: 3;
TEXT_VIEW_SCROLL_INCREMENT :: 2;

Text_View :: struct
{
	using base : Screen_View;
	filepath : string;
	has_file : bool;
	buffer : Gap_Buffer;
	
	text_area : struct
	{
		column,   line     : int;
		cursor_x, cursor_y : int;
		scroll_x, scroll_y : int;
	};

	line_count, wrapped_line_count : int;
	line_area_width : int;
	mouse_selection : bool;
}

init_text_view :: (view : *Text_View, screen : *Screen, x : int, y : int, w : int, h : int)
{
	view.screen = screen;
	view.type = .TEXT_VIEW;
	view.x = x;
	view.y = y;
	view.w = w;
	view.h = h;

	view.cursor_x = 0;
	view.cursor_y = 0;
	view.draw_cursor = true;
	view.filepath = FILEPATH;
	view.has_file = INIT_WITH_FILE;

	view.buffer = make_gap_buffer (5_000);

	#if INIT_WITH_FILE
	{
		ok := load_file (*view.buffer, view.filepath);
		if !ok  println ("Could not load file % into buffer", view.filepath);
	}

	view.line_count = get_line_count (view);
	view.wrapped_line_count = get_wrapped_line_count (view);
	view.line_area_width = get_line_area_width (view);
	set_cursor (*view.buffer, 0);
	view.text_area.cursor_x, view.text_area.cursor_y = get_text_area_cursor_position (view);
	scroll_text_area_to_cursor (view);
}

destroy_text_view :: (using view : *Text_View)
{
	destroy_gap_buffer (*buffer);
	memset (view, 0, size_of (Text_View));
}

resize_text_view :: (using view : *Text_View, new_w : int, new_h : int)
{
	w = new_w;
	h = new_h;
	wrapped_line_count = get_wrapped_line_count (view);
}

insert_rune_at_cursor :: (using view : *Text_View, codepoint : Rune)
{
	insert (*buffer, codepoint);
	line_count = get_line_count (view);
	wrapped_line_count = get_wrapped_line_count (view);
	line_area_width = get_line_area_width (view);
	scroll_text_area_to_cursor (view);
}

backspace_remove_rune_at_cursor :: (using view : *Text_View)
{
	if backspace_selection (*buffer)
	{
		line_count = get_line_count (view);
		wrapped_line_count = get_wrapped_line_count (view);
		line_area_width = get_line_area_width (view);
		scroll_text_area_to_cursor (view);
	}
}

remove_rune_at_cursor :: (using view : *Text_View)
{
	if delete_selection (*buffer)
	{
		line_count = get_line_count (view);
		wrapped_line_count = get_wrapped_line_count (view);
		line_area_width = get_line_area_width (view);
		scroll_text_area_to_cursor (view);
	}
}

backspace_remove_word_at_cursor :: (using view : *Text_View)
{
	if backspace_word (*buffer)
	{
		line_count = get_line_count (view);
		wrapped_line_count = get_wrapped_line_count (view);
		line_area_width = get_line_area_width (view);
		scroll_text_area_to_cursor (view);
	}
}

remove_word_at_cursor :: (using view : *Text_View)
{
	if delete_word (*buffer)
	{
		line_count = get_line_count (view);
		wrapped_line_count = get_wrapped_line_count (view);
		line_area_width = get_line_area_width (view);
		scroll_text_area_to_cursor (view);
	}
}

get_line_count :: (using view : *Text_View) -> int #must
{
	count := 1;
	for buffer
	{
		if it == #char "\n" count += 1;
	}

	return count;
}

get_wrapped_line_count :: (using view : *Text_View) -> int #must
{
	column := line_area_width;
	row    := 0;
	i := 0;
	while i < gap_buffer_count (buffer)
	{
		codepoint := buffer[i];
		column += 1;

		if codepoint == #char "\t"
		{
			while (column - line_area_width) % 4 != 0 && column < w
			{
				column += 1;
			}
		}
		
		if column >= w - 1 || codepoint == #char "\n"
		{
			column = line_area_width;
			row += 1;
		}

		i += 1;
	}

	return row + 1;
}

get_line_area_width :: (using view : *Text_View) -> int #must
{
	count := 0;
	current := line_count;
	while current > 0
	{
		current /= 10;
		count += 1;
	}

	return count + 2;
}

refresh_text_view :: (using view : *Text_View)
{
	update_text_area_column_and_line :: (using view : *Text_View)
	{
		text_area.column, text_area.line = 1;
		for i : 0..buffer.cursor-1
		{
			text_area.column += 1;

			if buffer[i] == #char "\n"
			{
				text_area.column = 1;
				text_area.line += 1;
			}
		}
	}

	get_cursor_of_first_displayed_line :: (using view : *Text_View) -> int #must
	{
		i := 0;
		x_pos := line_area_width;
		y_pos := 0;
		while i < gap_buffer_count (buffer) && y_pos < text_area.scroll_y
		{
			codepoint := buffer[i];
			x_pos += 1;

			if codepoint == #char "\t"
			{
				while (x_pos - line_area_width) % 4 != 0 && x_pos < w  x_pos += 1;
			}

			if x_pos > w - 1 || codepoint == #char "\n"
			{
				x_pos = line_area_width;
				y_pos += 1;
			}

			i += 1;
		}

		return i;
	}

	get_line_number_at_cursor :: (using view : *Text_View, pos : int) -> int #must
	{
		i := 0;
		line := 1;
		while i < pos && i < gap_buffer_count (buffer)
		{
			if buffer[i] == #char "\n"  line += 1;
			i += 1;
		}

		return line;
	}

	write_line_number :: (using view : *Text_View, line : int, y_pos : int)
	{
		i := line_area_width - 2;
		while line > 0
		{
			digit := line % 10;
			cell := get_cell_at_pos (view, i, y_pos);
			cell.codepoint = cast (Rune) (#char "0" + digit);
			i -= 1;
			line /= 10;
		}
	}

	for i : y..h - 1
	{
		for j : x..w - 1
		{
			cell := get_cell_at_pos (view, j, i);
			cell.codepoint = 0;
			cell.foreground_color = COLOR_WHITE;
			cell.background_color = COLOR_BLACK;
		}
	}

	{
		i := get_cursor_of_first_displayed_line (view);
		previous_line := 0;
		current_line := get_line_number_at_cursor (view, i);
		x_pos := line_area_width;
		y_pos := 0;
		while i < gap_buffer_count (buffer) && y_pos < h - 1
		{
			codepoint := buffer[i];
			cell := get_cell_at_pos (view, x_pos, y_pos);
			cell.codepoint = codepoint;
			
			if buffer.selection > 0 && i > buffer.cursor && i < buffer.cursor + buffer.selection  ||
			   buffer.selection < 0 && i >= buffer.cursor + buffer.selection && i < buffer.cursor ||
			   buffer.cursor == i
			{
				cell.foreground_color = COLOR_BLACK;
				if buffer.cursor == i  cell.background_color = COLOR_WHITE;
				else                   cell.background_color = Color.{ 200, 200, 200 };
			}
			else
			{
				cell.foreground_color = COLOR_WHITE;
				cell.background_color = COLOR_BLACK;
			}

			x_pos += 1;

			if codepoint == #char "\t"
			{
				while (x_pos - line_area_width) % 4 != 0 && x_pos < w
				{
					cell := get_cell_at_pos (view, x_pos, y_pos);
					cell.codepoint = 0;
					
					if buffer.selection > 0 && i > buffer.cursor && i < buffer.cursor + buffer.selection  ||
					   buffer.selection < 0 && i >= buffer.cursor + buffer.selection && i < buffer.cursor ||
					   buffer.cursor == i
					{
						cell.foreground_color = COLOR_BLACK;
						if buffer.cursor == i  cell.background_color = COLOR_WHITE;
						else                   cell.background_color = Color.{ 200, 200, 200 };
					}
					else
					{
						cell.foreground_color = COLOR_WHITE;
						cell.background_color = COLOR_BLACK;
					}

					x_pos += 1;
				}
			}

			if x_pos >= w - 1 || codepoint == #char "\n"
			{
				if current_line != previous_line  write_line_number (view, current_line, y_pos);
				previous_line = current_line;
				if codepoint == #char "\n"  current_line += 1;
				
				x_pos = line_area_width;
				y_pos += 1;
			}

			i += 1;
		}

		if buffer.cursor == gap_buffer_count (buffer)
		{
			cell := get_cell_at_pos (view, x_pos, y_pos);
			cell.foreground_color = COLOR_BLACK;
			cell.background_color = COLOR_WHITE;
		}

		if y_pos < h - 1  write_line_number (view, current_line, y_pos);
	}

	for x_pos : 0..w - 1
	{
		cell := get_cell_at_pos (view, x_pos, h - 1);
		cell.foreground_color = COLOR_BLACK;
		cell.background_color = COLOR_WHITE;
	}

	update_text_area_column_and_line (view);

	{
		// Write the filepath
		i := 0;
		x_pos := 1;
		y_pos := h - 1;
		while i < filepath.count && x_pos < w
		{
			codepoint, size := utf8_rune_at_byte (filepath, xx i);
			cell := get_cell_at_pos (view, x_pos, y_pos);
			cell.codepoint = codepoint;
			i += xx size;
			x_pos += 1;
		}

		x_pos = w - 1;

		// Write the column and line in the text
		right_part := sprint ("    (%,%)    UTF-8    LF  ", text_area.column, text_area.line);
		defer free (right_part);
		i = right_part.count - 1;
		while i >= 0 && x_pos >= 0
		{
			cell := get_cell_at_pos (view, x_pos, y_pos);
			if is_space (right_part[i])  cell.codepoint = 0;
			else                         cell.codepoint = right_part[i];
			i -= 1;
			x_pos -= 1;
		}
	}

	//text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
	cursor_x = text_area.cursor_x + line_area_width;
	cursor_y = text_area.cursor_y - text_area.scroll_y;
}

get_text_area_cursor_position :: (using view : *Text_View) -> int, int #must
{
	column := line_area_width;
	line   : int;
	for i : 0..buffer.cursor-1
	{
		column += 1;
		if buffer[i] == #char "\t"
		{
			while (column - line_area_width) % 4 != 0 && column < w
			{
				column += 1;
			}
		}

		if column > w - 1 || buffer[i] == #char "\n"
		{
			column = line_area_width;
			line += 1;
		}
	}

	return column - line_area_width, line;
}

move_text_area_cursor_to_target :: (using view : *Text_View, target_x : int, target_y : int, select := false)
{
	// @Speed (stefan): This is sloooooooooooow
	i      := 0;
	column := line_area_width;
	row    := 0;
	while i < gap_buffer_count (buffer) && row < target_y
	{
		column += 1;
		if buffer[i] == #char "\t"
		{
			while (column - line_area_width) % 4 != 0 && column < w
			{
				column += 1;
			}
		}

		if column > w - 1 || buffer[i] == #char "\n"
		{
			column = line_area_width;
			row += 1;
		}

		i += 1;
	}

	column = line_area_width;
	while i < gap_buffer_count (buffer) && column < target_x
	{
		column += 1;
		if buffer[i] == #char "\t"
		{
			while (column - line_area_width) % 4 != 0 && column < w
			{
				column += 1;
			}
		}

		if column > w - 1 || buffer[i] == #char "\n"
		{
			break;
		}

		i += 1;
	}

	if select  select_to (*buffer, i);
	else       set_cursor (*buffer, i);
	text_area.cursor_x  = column - line_area_width;
	text_area.cursor_y  = row;
	scroll_text_area_to_cursor (view);
}

move_text_area_cursor_up :: inline (using view : *Text_View, amount := 1)
{
	column, row := get_text_area_cursor_position (view);
	move_text_area_cursor_to_target (view, column + line_area_width, clamp (row - amount, 0, row));
}

move_text_area_cursor_down :: inline (using view : *Text_View, amount := 1)
{
	column, row := get_text_area_cursor_position (view);
	move_text_area_cursor_to_target (view, column + line_area_width, row + amount);
}

move_text_area_cursor_left :: inline (using view : *Text_View)
{
	if move_cursor_backward (*buffer)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

move_text_area_cursor_right :: inline (using view : *Text_View)
{
	if move_cursor_forward (*buffer)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

text_area_select_word_at_cursor :: inline (using view : *Text_View)
{
	select_word_at_cursor (*buffer);
	text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
	scroll_text_area_to_cursor (view);
}

skip_word_right :: inline (using view : *Text_View)
{
	if skip_word_forward (*buffer)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

skip_word_left :: inline (using view : *Text_View)
{
	if skip_word_backward (*buffer)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

move_text_area_cursor_to_buffer_start :: inline (using view : *Text_View)
{
	if set_cursor (*buffer, 0)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

move_text_area_cursor_to_buffer_end :: inline (using view : *Text_View)
{
	if set_cursor (*buffer, gap_buffer_count (buffer))
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

text_area_select_all :: inline (using view : *Text_View)
{
	set_cursor (*buffer, 0);
	select_to (*buffer, gap_buffer_count (buffer));
	text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
	scroll_text_area_to_cursor (view);
}

text_area_select_up :: inline (using view : *Text_View)
{
	column, row := get_text_area_cursor_position (view);
	move_text_area_cursor_to_target (view, column + line_area_width, row - 1, select = true);
}

text_area_select_down :: inline (using view : *Text_View)
{
	column, row := get_text_area_cursor_position (view);
	move_text_area_cursor_to_target (view, column + line_area_width, row + 1, select = true);
}

text_area_select_left :: inline (using view : *Text_View)
{
	if select_backward (*buffer)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

text_area_select_right :: inline (using view : *Text_View)
{
	if select_forward (*buffer)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

text_area_select_word_left :: inline (using view : *Text_View)
{
	if select_word_backward (*buffer)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

text_area_select_word_right :: inline (using view : *Text_View)
{
	if select_word_forward (*buffer)
	{
		text_area.cursor_x, text_area.cursor_y = get_text_area_cursor_position (view);
		scroll_text_area_to_cursor (view);
	}
}

scroll_text_area_to_cursor :: inline (using view : *Text_View)
{
	// @Cleanup (stefan): There's probably a better way to do it without loops.
	while text_area.cursor_y < text_area.scroll_y + min (text_area.cursor_y, TEXT_VIEW_SCROLL_MARGIN)
	{
		scroll_text_area_up (view);
	}

	while text_area.cursor_y - text_area.scroll_y > h - TEXT_VIEW_SCROLL_MARGIN - 1
	{
		scroll_text_area_down (view);
	}
}

scroll_text_area_up :: inline (using view : *Text_View, amount := 1)
{
	text_area.scroll_y = clamp (text_area.scroll_y - amount, 0, wrapped_line_count - 1);
}

scroll_text_area_down :: inline (using view : *Text_View, amount := 1)
{
	text_area.scroll_y = clamp (text_area.scroll_y + amount, 0, wrapped_line_count - 1 - TEXT_VIEW_SCROLL_MARGIN);
}

text_view_handle_event :: (using view : *Text_View, event : Event)
{
	// @Cleanup
	if event.type == .KEY_PRESS || event.type == .KEY_REPEAT
	{
		if event.key_event.key_code ==
		{
		case .UP;
			if event.key_event.mods == .CONTROL
			{
				move_text_area_cursor_to_buffer_start (view);
			}
			else if event.key_event.mods == .SHIFT
			{
				text_area_select_up (view);
			}
			else
			{
				move_text_area_cursor_up (view);
			}

		case .DOWN;
			if event.key_event.mods == .CONTROL
			{
				move_text_area_cursor_to_buffer_end (view);
			}
			else if event.key_event.mods == .SHIFT
			{
				text_area_select_down (view);
			}
			else
			{
				move_text_area_cursor_down (view);
			}

		case .LEFT;
			if event.key_event.mods == .CONTROL
			{
				skip_word_left (view);
			}
			else if event.key_event.mods == .SHIFT
			{
				text_area_select_left (view);
			}
			else if (event.key_event.mods & .SHIFT) && (event.key_event.mods & .CONTROL)
			{
				text_area_select_word_left (view);
			}
			else
			{
				move_text_area_cursor_left (view);
			}
		
		case .RIGHT;
			if event.key_event.mods == .CONTROL
			{
				skip_word_right (view);
			}
			else if event.key_event.mods == .SHIFT
			{
				text_area_select_right (view);
			}
			else if (event.key_event.mods & .SHIFT) && (event.key_event.mods & .CONTROL)
			{
				text_area_select_word_right (view);
			}
			else
			{
				move_text_area_cursor_right (view);
			}

		case .BACKSPACE;
			if event.key_event.mods == .CONTROL && buffer.selection == 0
			{
				backspace_remove_word_at_cursor (view);
			}
			else
			{
				backspace_remove_rune_at_cursor (view);
			}

		case .DELETE;
			if event.key_event.mods == .CONTROL
			{
				remove_word_at_cursor (view);
			}
			else
			{
				remove_rune_at_cursor (view);
			}

		case .PAGE_UP;    move_text_area_cursor_up (view, h - 1);
		case .PAGE_DOWN;  move_text_area_cursor_down (view, h - 1);
		}

		if event.key_event.mods == .CONTROL
		{
			if event.key_event.key_code ==
			{
			case .A; text_area_select_all (view);
			case .S;
				written, ok := write_gap_buffer_to_file (*buffer, OUTPUT_FILE);
				if ok  log_to_screen (screen, "Saved buffer to '%' (% bytes).", OUTPUT_FILE, written);
				else   log_to_screen (screen, "Failed to save buffer to '%' (% bytes).", OUTPUT_FILE, written);
			
			case .Z;
				if undo_operation (*buffer)
				{
					line_count = get_line_count (view);
					wrapped_line_count = get_wrapped_line_count (view);
					line_area_width = get_line_area_width (view);
					scroll_text_area_to_cursor (view);
				}

			case .Y;
				if redo_operation (*buffer)
				{
					line_count = get_line_count (view);
					wrapped_line_count = get_wrapped_line_count (view);
					line_area_width = get_line_area_width (view);
					scroll_text_area_to_cursor (view);
				}

			}
		}
	}
	else if event.type == .TEXT_INPUT
	{
		insert_rune_at_cursor (view, event.text_input_event.codepoint);
	}
	else if event.type == .MOUSE_BUTTON_PRESS || event.type == .MOUSE_BUTTON_REPEAT
	{
		if event.mouse_button_event.button == .LEFT
		{
			mouse_selection = true;
			target_x, target_y := screen_coordinates_to_cell_coordinates (event.window, event.mouse_button_event.mouse_x, event.mouse_button_event.mouse_y);
			target_x -= x;
			target_y -= y;
			move_text_area_cursor_to_target (view, target_x, target_y + text_area.scroll_y);
			if event.type == .MOUSE_BUTTON_REPEAT  text_area_select_word_at_cursor (view);
		}
	}
	else if event.type == .MOUSE_BUTTON_RELEASE
	{
		if event.mouse_button_event.button == .LEFT
		{
			mouse_selection = false;
		}
	}
	else if event.type == .MOUSE_MOVE
	{
		if mouse_selection
		{
			target_x, target_y := screen_coordinates_to_cell_coordinates (event.window, event.mouse_move_event.x, event.mouse_move_event.y);
			target_x -= x;
			target_y -= y;
			move_text_area_cursor_to_target (view, target_x, target_y + text_area.scroll_y, select = true);
		}
	}
	else if event.type == .MOUSE_WHEEL
	{
		     if event.mouse_wheel_event.y > 0  scroll_text_area_down (view, TEXT_VIEW_SCROLL_INCREMENT);
		else if event.mouse_wheel_event.y < 0  scroll_text_area_up   (view, TEXT_VIEW_SCROLL_INCREMENT);
	}
}
