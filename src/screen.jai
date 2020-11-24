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
		if view == active_view || view.refresh_if_inactive
		{
			if view.type == .TEXT_VIEW
			{
				refresh_text_view (cast (*Text_View) view);
			}
		}
	}
}

get_cell_at_pos :: inline (using screen : *Screen, pos_x : int, pos_y : int) -> *Screen_Element
{
	assert (pos_x >= 0 && pos_x < cols && pos_y >= 0 && pos_y < rows);
	
	return *cells[pos_y + rows * pos_x];
}

Screen_View_Type :: enum
{
	TEXT_VIEW;
}

Screen_View :: struct
{
	screen : *Screen;
	type : Screen_View_Type;
	x, y, w, h : int;
	cursor_x, cursor_y : int;
	draw_cursor : bool;
	refresh_if_inactive : bool;
}

get_cell_at_pos :: inline (using view : *Screen_View, pos_x : int, pos_y : int) -> *Screen_Element
{
	return get_cell_at_pos (screen, x + pos_x, y + pos_y);
}
