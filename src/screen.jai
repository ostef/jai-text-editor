INIT_TEXT_VIEW_WITH_CURRENT_FILE :: true;

Screen_Element :: struct
{
	codepoint : Rune;
	foreground_color : Color;
	background_color : Color;
}

Screen :: struct
{
	cells : []Screen_Element;
	cols : int;
	rows : int;
	views : [..]*Screen_View;
	active_view : *Screen_View;
}

init_screen :: (screen : *Screen, cols : int, rows : int)
{
	screen.cells = NewArray (cols * rows, Screen_Element);
	screen.cols = cols;
	screen.rows = rows;
	view := New (Text_View);
	init_text_view (view, screen, 0, 0, cols, rows - 1);
	array_reserve (*screen.views, 10);
	array_add (*screen.views, view);
	screen.active_view = view;
}

destroy_screen :: (using screen : *Screen)
{
	for view : views
	{
		if view.type ==
		{
			case .TEXT_VIEW; destroy_text_view (cast (*Text_View) view);
		}

		free (view);
	}

	array_reset (*views);
	free (cells.data);
	memset (screen, 0, size_of (Screen));
}

screen_handle_event :: inline (using screen : *Screen, event : Event)
{
	if active_view.type ==
	{
		case .TEXT_VIEW; text_view_handle_event (cast (*Text_View) active_view, event);
	}
}

navigate_screen_views :: (using screen : *Screen)
{
	// @Note (stefan): We might want a better rule for navigating view than switching
	// to the next view by id. For example we could do:
	/*
	 * VIEW 1   | VIEW 2  | VIEW 4  |
	 *         -->       -->        |
	 *    ^     |         |         |
	 * ---|---------------|         |
	 *         |          |         |
	 * VIEW 0 <- VIEW 3  <--        |
	 *         |          |         |
	 * ------------------------------
	 * ------------------------------
	 */
	for i : 0..views.count - 1
	{
		if active_view == views[i]
		{
			active_view = views[(i + 1) % views.count];
	
			break;
		}
	}
}

switch_to_view_at_position :: inline (using screen : *Screen, x : int, y : int)
{
	for view : views
	{
		if x >= view.x && x < view.x + view.w &&
		   y >= view.y && y < view.y + view.h
		{
			screen.active_view = view;

			break;
		}
	}
}

refresh_screen :: inline (using screen : *Screen)
{
	for view : views
	{
		if view.type == .TEXT_VIEW
		{
			refresh_text_view (cast (*Text_View) view);
		}
	}
}

Screen_View_Type :: enum
{
	TEXT_VIEW;
}

Screen_View :: struct
{
	screen : *Screen;
	type : Screen_View_Type;
	x : int;
	y : int;
	w : int;
	h : int;
	cursor_x, cursor_y : int;
	draw_cursor : bool;
}

Text_View :: struct
{
	using base : Screen_View;
	filepath : string;
	has_file : bool;
	buffer : [..]Rune;
	cursor : int;
	xoffset : int;
	col_in_text : int;
	line_in_text : int;
	line_count : int;
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
	view.filepath = #file;
	view.has_file = false;
	view.xoffset = 1;

	#if INIT_TEXT_VIEW_WITH_CURRENT_FILE
	{
		data, ok := read_entire_file (#file);
		assert (ok, "Could not read file %", #file);
		defer free (data);
		array_reserve (*view.buffer, data.count);
		
		i := 0;
		while i < data.count
		{
			codepoint, size := utf8_rune_at_byte (data, xx i);
			if codepoint != #char "\r"  array_add (*view.buffer, codepoint);	// Ignore freaking '\r'
			i += xx size;
		}
	}
	else
	{
		array_reserve (*view.buffer, 1024);
	}
	
	view.cursor = 0;
}

destroy_text_view :: (using view : *Text_View)
{
	array_reset (*buffer);
	memset (view, 0, size_of (Text_View));
}

// @Todo (stefan)
resize_text_view :: (using view : *Text_View)
{
}

insert_rune_at_cursor :: (using view : *Text_View, codepoint : Rune)
{
	array_insert_at (*buffer, codepoint, cursor);
	move_text_view_cursor_right (view);
}

backspace_remove_rune_at_cursor :: (using view : *Text_View)
{
	if buffer.count > 0 && cursor > 0
	{
		array_ordered_remove_by_index (*buffer, cursor - 1);
		move_text_view_cursor_left (view);
	}
}

remove_rune_at_cursor :: (using view : *Text_View)
{
	if buffer.count > 0 && cursor < buffer.count
	{
		array_ordered_remove_by_index (*buffer, cursor);
	}
}

#scope_file

write_string_to_view :: (using view : *Screen_View, runes : []Rune, x_min : int, y_min : int, x_max : int = -1, y_max : int = -1, foreground_color := Color.{ 255, 255, 255, 255 }, background_color := Color.{ 0, 0, 0, 255 })
{
	if x_max == -1  x_max = w;
	if y_max == -1  y_max = h;
	x_max = clamp (x_max, 0, w);
	y_max = clamp (y_max, 0, h);

	i : u64;
	x_pos := x_min;
	y_pos := y_min;
	while i < xx runes.count && y_pos < y_max
	{
		codepoint := runes[i];
		cell := *screen.cells[(y + y_pos) + screen.rows * (x + x_pos)];
		cell.codepoint = codepoint;
		cell.foreground_color = foreground_color;
		cell.background_color = background_color;
		x_pos += 1;

		if codepoint == #char "\t"
		{
			while x_pos % 4 != 0 && x_pos < x_max
			{
				cell := *screen.cells[(y + y_pos) + screen.rows * (x + x_pos)];
				cell.codepoint = 0;
				cell.foreground_color = foreground_color;
				cell.background_color = background_color;
				x_pos += 1;
			}
		}

		if x_pos >= x_max - 1 || codepoint == #char "\n"
		{
			x_pos = x_min;
			y_pos += 1;
		}

		i += 1;
	}
}

write_string_to_view :: (using view : *Screen_View, str : string, x_min : int, y_min : int, x_max : int = -1, y_max : int = -1, foreground_color := Color.{ 255, 255, 255, 255 }, background_color := Color.{ 0, 0, 0, 255 })
{
	// @Note (stefan): We could do a better version without allocating but that would require 2 similar procedures to maintain.
	// I dunno if we should choose the better version over the current one.
	runes, valid := utf8_string_to_runes (str, __temporary_allocator);
	if valid  write_string_to_view (view, runes, x_min, y_min, x_max, y_max, foreground_color, background_color);
}

get_line_count :: (buffer : []Rune) -> int
{
	count := 1;
	for rune : buffer
	{
		if rune == #char "\n" count += 1;
	}

	return count;
}

update_text_view_xoffset :: (using view : *Text_View)
{
	// xoffset is the length of the line number string plus one
	count := 0;
	current := line_count;
	while current > 0
	{
		current /= 10;
		count += 1;
	}

	xoffset = count + 1;
}

refresh_text_view :: (using view : *Text_View)
{
	write_line_number :: (using view : *Text_View, line : int)
	{
		yoffset := line - 1;
		i := xoffset - 2;
		while line > 0
		{
			digit := line % 10;
			cell := *screen.cells[y + yoffset + screen.rows * (x + i)];
			cell.codepoint = cast (Rune) (#char "0" + digit);
			i -= 1;
			line /= 10;
		}
	}

	column, line := get_text_view_cursor_pos (view);
	col_in_text = column;
	line_in_text = line;
	line_count = get_line_count (view.buffer);
	update_text_view_xoffset (view);
	cursor_x = col_in_text + xoffset;
	cursor_y = line_in_text;

	for i : y..h-1
	{
		for j : x + xoffset..w-1
		{
			cell := *screen.cells[i + screen.rows * j];
			cell.codepoint = 0;
			cell.foreground_color = COLOR_WHITE;
			cell.background_color = COLOR_BLACK;
		}
	}

	// @Note (stefan): Currently, the line number we have does not take into account
	// wordwrapping. Everything is a mess right now so we should do a cleanup.
	line_number := 1;
	for i : y..h-2
	{
		for j : x..x + xoffset - 1
		{
			cell := *screen.cells[i + screen.rows * j];
			cell.codepoint = 0;
			cell.foreground_color = COLOR_WHITE;
			cell.background_color = Color.{ 16, 16, 16, 255 };
		}

		if line_number <= line_count  write_line_number (view, line_number);
		line_number += 1;
	}

	write_string_to_view (view, buffer, xoffset, 0, w, h - 1);

	for i : x..x + w - 1
	{
		cell := *screen.cells[y + h - 1 + screen.rows * (x + i)];
		cell.codepoint = #char "=";
		cell.foreground_color = COLOR_BLACK;
		cell.background_color = COLOR_WHITE;
	}

	write_string_to_view (view, filepath, 1, view.h - 1, foreground_color = COLOR_BLACK, background_color = COLOR_WHITE);
}

get_text_view_cursor_pos :: (using view : *Text_View) -> int, int
{
	column := xoffset;
	line : int;
	for i : 0..cursor-1
	{
		column += 1;
		if buffer[i] == #char "\t"
		{
			while column % 4 != 0 && column < w
			{
				column += 1;
			}
		}

		if column > w - 1 || buffer[i] == #char "\n"
		{
			column = xoffset;
			line += 1;
		}
	}

	return column - xoffset, line;
}

move_text_view_cursor_to_target :: (using view : *Text_View, target_x : int, target_y : int)
{
	i := 0;
	column := xoffset;
	row : int;
	while i < buffer.count && row < target_y
	{
		column += 1;
		if buffer[i] == #char "\t"
		{
			while column % 4 != 0 && column < w
			{
				column += 1;
			}
		}

		if column > w - 1 || buffer[i] == #char "\n"
		{
			column = xoffset;
			row += 1;
		}

		i += 1;
	}

	column = xoffset;
	while i < buffer.count && column < target_x
	{
		column += 1;
		if buffer[i] == #char "\t"
		{
			while column % 4 != 0 && column < w
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

	cursor = i;
}

move_text_view_cursor_up :: (using view : *Text_View)
{
	column, row := get_text_view_cursor_pos (view);
	move_text_view_cursor_to_target (view, column + xoffset, row - 1);
}

move_text_view_cursor_down :: (using view : *Text_View)
{
	column, row := get_text_view_cursor_pos (view);
	move_text_view_cursor_to_target (view, column + xoffset, row + 1);
}

move_text_view_cursor_left :: (using view : *Text_View)
{
	// @Note (stefan): Maybe we should also update the cursor position in the view, instead of doing it when refreshing.
	// This would also mean that we can rely on cursor_x and cursor_y being correct in other procedures such as move_cursor_up/down.
	cursor = clamp (cursor - 1, 0, buffer.count);
}

move_text_view_cursor_right :: (using view : *Text_View)
{
	cursor = clamp (cursor + 1, 0, buffer.count);
}

text_view_handle_event :: (using view : *Text_View, event : Event)
{
	if event.type == .KEY_PRESS || event.type == .KEY_REPEAT
	{
		if event.key_event.key ==
		{
			case GLFW_KEY_UP;    move_text_view_cursor_up (view);
			case GLFW_KEY_DOWN;  move_text_view_cursor_down (view);
			case GLFW_KEY_LEFT;  move_text_view_cursor_left (view);
			case GLFW_KEY_RIGHT; move_text_view_cursor_right (view);
			case GLFW_KEY_ENTER; insert_rune_at_cursor (view, #char "\n");
			case GLFW_KEY_TAB;   insert_rune_at_cursor (view, #char "\t");
			case GLFW_KEY_BACKSPACE;  backspace_remove_rune_at_cursor (view);
			case GLFW_KEY_DELETE;     remove_rune_at_cursor (view);
		}
	}
	else if event.type == .CHAR_INPUT
	{
		insert_rune_at_cursor (view, event.char_input_event.codepoint);
	}
	else if event.type == .MOUSE_BUTTON_PRESS
	{
		if event.mouse_button_event.button == GLFW_MOUSE_BUTTON_LEFT
		{
			target_x := event.mouse_button_event.col - x;
			target_y := event.mouse_button_event.row - y;
			move_text_view_cursor_to_target (view, target_x, target_y);
		}
	}
}
