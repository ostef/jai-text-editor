Color :: struct
{
	r, g, b, a : u8;
}

color_to_vector3 :: (color : Color) -> Vector3
{
	return make_vector3 (color.r / 255.0, color.g / 255.0, color.b / 255.0);
}

Screen_Element :: struct
{
	codepoint : Rune;
	foreground_color : Color;
	background_color : Color;
}

Screen_Buffer :: struct
{
	columns : int;
	rows : int;
	cells : *Screen_Element;	// Row major, this is more efficient for writing top to bottom
	views : [..]Screen_View;
	active_view : *Screen_View;
}

Screen_View :: struct
{
	buffer : *Screen_Buffer;
	id : int;
	x : int;
	y : int;
	w : int;
	h : int;
	cursor_x : int;
	cursor_y : int;
}

init_screen_buffer :: (buffer : *Screen_Buffer, columns : int, rows : int)
{
	buffer.columns = columns;
	buffer.rows = rows;
	buffer.cells = cast (*Screen_Element) alloc (size_of (Screen_Element) * columns * rows);
	
	for i : 0..columns * rows - 1
	{
		cell := *buffer.cells[i];
		cell.codepoint = 0;
		cell.foreground_color = Color.{ 255, 255, 255, 255 };
		cell.background_color = Color.{ 0, 0, 0, 0 };
	}

	// White bottom line
	for i : 0..columns-1
	{
		cell := *buffer.cells[rows - 1 + rows * i];
		cell.codepoint = 0;
		cell.foreground_color = Color.{ 255, 255, 255, 255 };
		cell.background_color = Color.{ 255, 255, 255, 255 };
	}

	array_reserve (*buffer.views, 10);
	buffer.active_view = make_screen_view (buffer, 0, 0, columns, rows - 1);
}

destroy_screen_buffer :: (buffer : *Screen_Buffer)
{
	array_reset (*buffer.views);
	free (buffer.cells);
	buffer.columns = 0;
	buffer.rows = 0;
}

resize_screen_buffer :: (buffer : *Screen_Buffer, columns : int, rows : int)
{
	if columns < buffer.columns && rows < buffer.rows  return;
	if columns == 0 || rows == 0  return;
	new_cells := cast (*Screen_Element) alloc (size_of (Screen_Element) * columns * rows);

	defer
	{
		free (buffer.cells);
		buffer.cells = new_cells;
		buffer.columns = columns;
		buffer.rows = rows;
	}

	new_i, new_j := 0;
	for j : 0..buffer.rows-1
	{
		for i : 0..buffer.columns-1
		{
			cell := buffer.cells[i + buffer.columns * j];
			new_cells[new_i + columns * new_j] = cell;
			new_i += 1;
	
			if cell.codepoint == #char "\n" || new_i == columns - 1
			{
				new_i = 0;
				new_j += 1;
			}
		}
	}
}

get_screen_cell :: inline (using buffer : *Screen_Buffer, x : int, y : int) -> *Screen_Element
{
	return *cells[y + rows * x];
}

get_screen_cell_at_cursor :: inline (using view : *Screen_View) -> *Screen_Element
{
	return *buffer.cells[(y + cursor_y) + buffer.rows * (x + cursor_x)];
}

move_cursor_up :: inline (using view : *Screen_View)
{
	if cursor_y > 0  cursor_y -= 1;
}

move_cursor_down :: inline (using view : *Screen_View)
{
	if cursor_y < h - 1  cursor_y += 1;
}

move_cursor_left :: inline (using view : *Screen_View)
{
	if cursor_x > 0  cursor_x -= 1;
}

move_cursor_right :: inline (using view : *Screen_View)
{
	if cursor_x < w - 1  cursor_x += 1;
}

set_cursor_position :: inline (view : *Screen_View, x : int, y : int)
{
	view.cursor_x = clamp (x, 0, view.w - 1);
	view.cursor_y = clamp (y, 0, view.h - 1);
}

set_cursor_absolute_position :: inline (using buffer : *Screen_Buffer, x : int, y : int)
{
	for *view : views
	{
		if x >= view.x && x < view.x + view.w &&
		   y >= view.y && y < view.y + view.h
		{
			set_active_screen_view (buffer, view);
			set_cursor_position (view, x - view.x, y - view.y);
		}
	}
}

//write_to_screen :: inline (using buffer : *Screen_Buffer, codepoint : Rune, foreground_color := Color.{ 255, 255, 255, 255 }, background_color := Color.{ 0, 0, 0, 255 })
//{
//	cells[cursor_y + rows * cursor_x].codepoint = codepoint;
//	cells[cursor_y + rows * cursor_x].foreground_color = foreground_color;
//	cells[cursor_y + rows * cursor_x].background_color = background_color;
//
//	if cursor_x == columns - 1 || codepoint == #char "\n"
//	{
//		cursor_x = 0;
//		cursor_y += 1;
//	}
//	else
//	{
//		cursor_x += 1;
//	}
//}

make_screen_view_horizontal :: (using buffer : *Screen_Buffer) -> *Screen_View
{
	active_view.w /= 2;
	view := make_screen_view (buffer, active_view.x + active_view.w + 1, active_view.y, active_view.w - 1, active_view.h);
	
	// Vertical border
	for j : active_view.y..active_view.y + active_view.h - 1
	{
		cell := get_screen_cell (buffer, active_view.x + active_view.w, j);
		cell.codepoint = #char "|";
		cell.foreground_color = Color.{ 0, 0, 0, 255 };
		cell.background_color = Color.{ 255, 255, 255, 255 };
	}

	return view;
}

make_screen_view_vertical :: (using buffer : *Screen_Buffer) -> *Screen_View
{
	active_view.h /= 2;
	view := make_screen_view (buffer, active_view.x, active_view.y + active_view.h + 1, active_view.w, active_view.h - 1);
	
	// Horizontal border
	for i : active_view.x..active_view.x + active_view.w - 1
	{
		cell := get_screen_cell (buffer, i, active_view.y + active_view.h);
		cell.codepoint = #char "-";
		cell.foreground_color = Color.{ 0, 0, 0, 255 };
		cell.background_color = Color.{ 255, 255, 255, 255 };
	}

	return view;
}

set_active_screen_view :: inline (using buffer : *Screen_Buffer, view : *Screen_View)		// For now this procedure is just a useless wrapper  but we might want to add things to it later
{
	active_view = view;
}

print_to_screen :: (using view : *Screen_View, str : string, foreground_color := Color.{ 255, 255, 255, 255 }, background_color := Color.{ 0, 0, 0, 255 })
{
	i := 0;
	while i < str.count && cursor_y < h
	{
		char, size := utf8_rune_at_byte (str, xx i);
		cell := get_screen_cell_at_cursor (view);
		cell.codepoint = char;
		cell.foreground_color = foreground_color;
		if is_space (char)  cell.foreground_color = Color.{ 100, 100, 100, 255 };
		cell.background_color = background_color;
		cursor_x += 1;
			
		if char == #char "\t"
		{
			while cursor_x % 4 != 0 && cursor_x < w
			{
				cell := get_screen_cell_at_cursor (view);
				cell.codepoint = 0;
				cell.foreground_color = foreground_color;
				cell.background_color = background_color;
				cursor_x += 1;
			}
		}

		if cursor_x >= w - 1 || char == #char "\n"
		{
			cursor_x = 0;
			cursor_y += 1;
		}

		i += xx size;
	}
}

navigate_views :: (using buffer : *Screen_Buffer)
{
	for i : 0..views.count - 1
	{
		if active_view == *views[i]
		{
			active_view = *views[(i + 1) % views.count];
	
			break;
		}
	}
}

#scope_file

make_screen_view :: (using buffer : *Screen_Buffer, x : int, y : int, w : int, h : int) -> *Screen_View
{
	view := array_add (*views);
	view.buffer = buffer;
	view.id = views.count - 1;
	view.x = x;
	view.y = y;
	view.w = w;
	view.h = h;

	return view;
}
