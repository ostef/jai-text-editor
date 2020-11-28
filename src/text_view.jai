#scope_file
INIT_WITH_FILE :: true;
FILEPATH       :: #file;
#scope_export

/*
 * One of the biggest difficulty I encountered has to do with the fact that the text view has to know
 * where things are placed on the screen to be able to move the cursor properly and select things with
 * the mouse. We essentially want to have the cursor position, line number display width ect. up to date at all
 * time. Luckily, there only a handful of procedures that modify the way things are placed on the screen:
 *    * Scroll up, down, left and right,
 *    * Inserting, backspace remove, remove rune at cursor,
 *    * Moving the cursor (this one does not directly affect the final render, just the cursor placement).
 *
 * And the following procedures need to know how things are placed on the screen:
 *    * Moving the cursor,
 *    * Refreshing the text view.
 *
 * On the other hand, usually only one thing is done per event, so we would want to update the positions of things
 * one time per refresh. (Add a dirty flag ???).
 *
 * Another big difficulty is the different names there are for cursor. Currently, we want to know the cursor position
 * in the view itself. This is stored in the Screen_View struct as cursor_x and cursor_y. We also want to know the
 * cursor position in the text itself that is drawn on the screen (the column and line if you will). And we also
 * want to store the cursor in the buffer. Procedures that change the cursor in the view, the cursor in the text
 * or the cursor in the buffer all have "cursor" in their name, but it's often difficult to know what it refers to.
 * In general, the things are all over the place, we don't know if the column and row that we pass are relative to
 * the text area, or if they're absolute or something. Clean this up!!		@Cleanup
 *
 *																		ostef, November 24th 2020
 */

TEXT_VIEW_SCROLL_MARGIN :: 3;
TEXT_VIEW_SCROLL_INCREMENT :: 2;

Text_View :: struct
{
	using base : Screen_View;
	filepath : string;
	has_file : bool;
	buffer : Gap_Buffer;
	col_in_text : int;
	line_in_text : int;
	scroll_x, scroll_y : int;
	line_count, wrapped_line_count : int;
	xoffset : int;
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
	view.has_file = false;

	#if INIT_WITH_FILE
	{
		data, ok := read_entire_file (FILEPATH);
		assert (ok, "Could not read file %", FILEPATH);
		defer free (data);
		view.buffer = make_gap_buffer (data.count);
		
		i := 0;
		newlines := 0;
		while i < data.count
		{
			codepoint, size := utf8_rune_at_byte (data, xx i);
			if codepoint != #char "\r" insert (*view.buffer, codepoint);	// Ignore freaking '\r'
			i += xx size;
		}
	}
	else
	{
		view.buffer = make_gap_buffer (5_000);
	}

	view.line_count = get_line_count (view);
	view.wrapped_line_count = get_wrapped_line_count (view);
	update_text_view_xoffset (view);
	view.col_in_text, view.line_in_text = get_text_view_cursor_pos_in_text (view);
	scroll_text_view_to_cursor (view);
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
	line_count = get_line_count (view);
	wrapped_line_count = get_wrapped_line_count (view);
	update_text_view_xoffset (view);
}

insert_rune_at_cursor :: (using view : *Text_View, codepoint : Rune)
{
	insert (*buffer, codepoint);
	// @Cleanup
	line_count = get_line_count (view);
	wrapped_line_count = get_wrapped_line_count (view);
	update_text_view_xoffset (view);
	scroll_text_view_to_cursor (view);
}

backspace_remove_rune_at_cursor :: (using view : *Text_View)
{
	if buffer.cursor > 0
	{
		backspace (*buffer);
		// @Cleanup
		line_count = get_line_count (view);
		wrapped_line_count = get_wrapped_line_count (view);
		update_text_view_xoffset (view);
		scroll_text_view_to_cursor (view);
	}
}

remove_rune_at_cursor :: (using view : *Text_View)
{
	if buffer.cursor < gap_buffer_count (buffer)
	{
		delete (*buffer);
		// @Cleanup
		line_count = get_line_count (view);
		wrapped_line_count = get_wrapped_line_count (view);
		update_text_view_xoffset (view);
		scroll_text_view_to_cursor (view);
	}
}

/*
write_string_to_view :: (using view : *Screen_View, runes : []Rune, x_min : int, y_min : int, x_max : int = -1, y_max : int = -1, foreground_color := COLOR_WHITE, background_color := COLOR_BLACK)
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

write_string_to_view :: (using view : *Screen_View, str : string, x_min : int, y_min : int, x_max : int = -1, y_max : int = -1, foreground_color := COLOR_WHITE, background_color := COLOR_BLACK)
{
	// @Note (stefan): We could do a better version without allocating but that would require 2 similar procedures to maintain.
	// I dunno if we should choose the better version over the current one.
	runes, valid := utf8_string_to_runes (str, __temporary_allocator);
	if valid  write_string_to_view (view, runes, x_min, y_min, x_max, y_max, foreground_color, background_color);
}
*/

get_line_count :: (using view : *Text_View) -> int
{
	count := 1;
	for buffer
	{
		if it == #char "\n" count += 1;
	}

	return count;
}

get_wrapped_line_count :: (using view : *Text_View) -> int
{
	column := xoffset;
	row    := 0;
	i := 0;
	while i < gap_buffer_count (buffer)
	{
		codepoint := buffer[i];
		column += 1;

		if codepoint == #char "\t"
		{
			while column % 4 != 0 && column < w
			{
				column += 1;
			}
		}
		
		if column >= w - 1 || codepoint == #char "\n"
		{
			column = xoffset;
			row += 1;
		}

		i += 1;
	}

	return row + 1;
}

update_text_view_xoffset :: (using view : *Text_View)
{
	// xoffset is the width of the line number area
	count := 0;
	current := line_count;
	while current > 0
	{
		current /= 10;
		count += 1;
	}

	xoffset = count + 2;
}

refresh_text_view :: (using view : *Text_View)
{
	get_cursor_of_first_displayed_line :: (using view : *Text_View) -> int
	{
		i := 0;
		x_pos := xoffset;
		y_pos := 0;
		while i < gap_buffer_count (buffer) && y_pos < scroll_y
		{
			codepoint := buffer[i];
			x_pos += 1;

			if codepoint == #char "\t"
			{
				while x_pos % 4 != 0 && x_pos < w  x_pos += 1;
			}

			if x_pos > w - 1 || codepoint == #char "\n"
			{
				x_pos = xoffset;
				y_pos += 1;
			}

			i += 1;
		}

		return i;
	}

	get_line_number_at_cursor :: (using view : *Text_View, pos : int) -> int
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
		i := xoffset - 2;
		while line > 0
		{
			digit := line % 10;
			cell := *screen.cells[(y + y_pos) + screen.rows * (x + i)];
			cell.codepoint = cast (Rune) (#char "0" + digit);
			i -= 1;
			line /= 10;
		}
	}

	for i : y..h - 1
	{
		for j : x..w - 1
		{
			cell := *screen.cells[(y + i) + screen.rows * (x + j)];
			cell.codepoint = 0;
			cell.foreground_color = COLOR_WHITE;
			cell.background_color = COLOR_BLACK;
		}
	}

	//line_count = get_line_count (view);
	//update_text_view_xoffset (view);

	{
		i := get_cursor_of_first_displayed_line (view);
		previous_line := 0;
		current_line := get_line_number_at_cursor (view, i);
		x_pos := xoffset;
		y_pos := 0;
		while i < gap_buffer_count (buffer) && y_pos < h
		{
			codepoint := buffer[i];
			cell := *screen.cells[(y + y_pos) + screen.rows * (x + x_pos)];
			cell.codepoint = codepoint;
			cell.foreground_color = COLOR_WHITE;
			cell.background_color = COLOR_BLACK;
			x_pos += 1;

			if codepoint == #char "\t"
			{
				while x_pos % 4 != 0 && x_pos < w
				{
					cell := *screen.cells[(y + y_pos) + screen.rows * (x + x_pos)];
					cell.codepoint = 0;
					cell.foreground_color = COLOR_WHITE;
					cell.background_color = COLOR_BLACK;
					x_pos += 1;
				}
			}

			if x_pos >= w - 1 || codepoint == #char "\n"
			{
				if current_line != previous_line  write_line_number (view, current_line, y_pos);
				previous_line = current_line;
				if codepoint == #char "\n"  current_line += 1;
				
				x_pos = xoffset;
				y_pos += 1;
			}

			i += 1;
		}

		write_line_number (view, current_line, y_pos);
	}

	col_in_text, line_in_text = get_text_view_cursor_pos_in_text (view);
	cursor_x = col_in_text + xoffset;
	cursor_y = line_in_text - scroll_y;
}

get_text_view_cursor_pos_in_text :: (using view : *Text_View) -> int, int
{
	column := xoffset;
	line   : int;
	for i : 0..buffer.cursor-1
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
	i      := 0;
	column := xoffset;
	row    := 0;
	while i < gap_buffer_count (buffer) && row < target_y
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
	while i < gap_buffer_count (buffer) && column < target_x
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

	set_cursor (*buffer, i);
	col_in_text  = column - xoffset;
	line_in_text = row;
	scroll_text_view_to_cursor (view);
}

move_text_view_cursor_up :: inline (using view : *Text_View)
{
	column, row := get_text_view_cursor_pos_in_text (view);
	move_text_view_cursor_to_target (view, column + xoffset, row - 1);
}

move_text_view_cursor_down :: inline (using view : *Text_View)
{
	column, row := get_text_view_cursor_pos_in_text (view);
	move_text_view_cursor_to_target (view, column + xoffset, row + 1);
}

move_text_view_cursor_left :: inline (using view : *Text_View)
{
	move_cursor_backward (*buffer);
	col_in_text, line_in_text = get_text_view_cursor_pos_in_text (view);
	scroll_text_view_to_cursor (view);
}

move_text_view_cursor_right :: inline (using view : *Text_View)
{
	move_cursor_forward (*buffer);
	col_in_text, line_in_text = get_text_view_cursor_pos_in_text (view);
	scroll_text_view_to_cursor (view);
}

move_text_view_cursor_to_buffer_start :: inline (using view : *Text_View)
{
	set_cursor (*buffer, 0);
	col_in_text, line_in_text = get_text_view_cursor_pos_in_text (view);
	scroll_text_view_to_cursor (view);
}

move_text_view_cursor_to_buffer_end :: inline (using view : *Text_View)
{
	set_cursor (*buffer, gap_buffer_count (buffer));
	col_in_text, line_in_text = get_text_view_cursor_pos_in_text (view);
	scroll_text_view_to_cursor (view);
}

scroll_text_view_to_cursor :: inline (using view : *Text_View)
{
	// @Cleanup (stefan): There's probably a better way to do it without loops.
	while line_in_text < scroll_y + min (line_in_text, TEXT_VIEW_SCROLL_MARGIN)
	{
		scroll_text_view_up (view);
	}

	while line_in_text - scroll_y > h - TEXT_VIEW_SCROLL_MARGIN
	{
		scroll_text_view_down (view);
	}
}

scroll_text_view_up :: inline (using view : *Text_View, amount := 1)
{
	scroll_y = clamp (scroll_y - amount, 0, wrapped_line_count - 1);
}

scroll_text_view_down :: inline (using view : *Text_View, amount := 1)
{
	scroll_y = clamp (scroll_y + amount, 0, wrapped_line_count - 1 - TEXT_VIEW_SCROLL_MARGIN);
}

text_view_handle_event :: (using view : *Text_View, event : Event)
{
	if event.type == .KEY_PRESS || event.type == .KEY_REPEAT
	{
		if event.key_event.key ==
		{
			case GLFW_KEY_UP;
				if event.key_event.mods == GLFW_MOD_CONTROL
				{
					move_text_view_cursor_to_buffer_start (view);
				}
				else
				{
					move_text_view_cursor_up (view);
				}

			case GLFW_KEY_DOWN;
				if event.key_event.mods == GLFW_MOD_CONTROL
				{
					move_text_view_cursor_to_buffer_end (view);
				}
				else
				{
					move_text_view_cursor_down (view);
				}

			case GLFW_KEY_LEFT;  move_text_view_cursor_left (view);
			case GLFW_KEY_RIGHT; move_text_view_cursor_right (view);
			case GLFW_KEY_ENTER; insert_rune_at_cursor (view, #char "\n");
			case GLFW_KEY_TAB;   insert_rune_at_cursor (view, #char "\t");
			case GLFW_KEY_BACKSPACE;  backspace_remove_rune_at_cursor (view);
			case GLFW_KEY_DELETE;     remove_rune_at_cursor (view);
			case GLFW_KEY_PAGE_UP;    scroll_text_view_up (view);
			case GLFW_KEY_PAGE_DOWN;  scroll_text_view_down (view);
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
			move_text_view_cursor_to_target (view, target_x, target_y + scroll_y);
		}
	}
	else if event.type == .SCROLL
	{
		if event.scroll_event.y > 0  scroll_text_view_down (view, TEXT_VIEW_SCROLL_INCREMENT);
		else                         scroll_text_view_up   (view, TEXT_VIEW_SCROLL_INCREMENT);
	}
}