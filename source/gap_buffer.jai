Gap_Buffer :: struct
{
	data   : *u8;
	count  : s64;
	cursor : s64;
	gap    : s64;
	lines  : [..]u32;
	line, column : s64;
	selection : s64;

	allocator : Allocator;
	allocator_data : *void;
}

init_gap_buffer :: (buffer : *Gap_Buffer, capacity : s64, allocator : Allocator, allocator_data := null)
{
	buffer.data   = alloc (capacity, allocator, allocator_data);
	buffer.count  = capacity;
	buffer.cursor = 0;
	buffer.gap    = capacity;
	buffer.selection = 0;
	buffer.lines = make_array (u32, 5000, heap_allocator);
	push_to_array (*buffer.lines, 0);
	buffer.line   = 0;
	buffer.column = 0;
	buffer.allocator = allocator;
	buffer.allocator_data = allocator_data;
}

reset_gap_buffer :: (using buffer : *Gap_Buffer)
{
	free (data, allocator, allocator_data);
	data   = null;
	count  = 0;
	cursor = 0;
	gap    = 0;
	reset_array (*lines);
	line   = 0;
	column = 0;
}

clear_gap_buffer :: (using buffer : *Gap_Buffer)
{
	cursor = 0;
	gap    = count;
	clear_array (*lines);
	push_to_array (*buffer.lines, 0);
	line   = 0;
	column = 0;
}

clone_to_string :: (buffer : Gap_Buffer, allocator : Allocator, allocator_data := null) -> string #must
{
	front := get_front_part (buffer);
	back  := get_back_part (buffer);
	result := alloc_string (front.count + back.count, allocator, allocator_data);
	if result
	{
		memcpy (result.data, front.data, front.count);
		memcpy (result.data + front.count, back.data, back.count);
	}

	return result;
}

#scope_file

split_current_line :: (using buffer : *Gap_Buffer)
{
	current     := lines[line];
	first_half  := column;
	second_half := current - first_half;
	// Split
	lines[line] = xx first_half;
	sorted_insert_to_array (*lines, line + 1, xx second_half);
}

merge_current_line_with_next_one :: (using buffer : *Gap_Buffer)
{
	if line == lines.count - 1 then return;

	lines[line] += lines[line + 1];
	sorted_remove_from_array (*lines, line + 1);
}

#scope_export

insert_at_cursor :: (using buffer : *Gap_Buffer, char : u8)
{
	if gap == 0 then grow_gap_buffer (buffer, 2);
	if selection != 0 then delete_selection (buffer);

	data[cursor] = char;
	cursor += 1;
	gap    -= 1;
	
	// Update line cache
	lines[line] += 1;
	column += 1;

	// Handle newline
	if char == #char "\n"
	{
		split_current_line (buffer);
		line += 1;
		column = 0;
	}
}

insert_at_cursor :: inline (using buffer : *Gap_Buffer, codepoint : u32)
{
	utf8 : [4]u8;
	size := utf8_encode (utf8, codepoint);
	for i : 0..size - 1
		insert_at_cursor (buffer, utf8[i]);
}

insert_at_cursor :: inline (using buffer : *Gap_Buffer, str : string)
{
	for i : 0..str.count - 1
		insert_at_cursor (buffer, str[i]);
}

backspace_selection :: (using buffer : *Gap_Buffer) -> bool
{
	if selection != 0 then return delete_selection (buffer);

	// @Todo (stefan): Handle multibyte characters
	if cursor > 0
	{
		cursor -= 1;
		gap    += 1;
		selection = 0;
		
		// Update line cache
		lines[line] -= 1;
		column -= 1;
		// Handle newline
		char := data[cursor];
		if char == #char "\n"
		{
			line -= 1;
			column = lines[line] - 1;
			merge_current_line_with_next_one (buffer);
		}
	}

	return false;
}

delete_selection :: (using buffer : *Gap_Buffer) -> bool
{
	// @Todo (stefan): Handle multibyte characters
	if cursor < gap_buffer_count (buffer) || selection != 0
	{
		if selection == 0
		{
			char := data[cursor + gap];
			gap += 1;
			// Update line cache
			lines[line] -= 1;
			if char == #char "\n"
			{
				merge_current_line_with_next_one (buffer);
			}
		}

		while selection < 0
		{
			select_backward (buffer);
			gap += 1;
		}

		while selection > 0
		{
			selection -= 1;
			gap += 1;
		}

		return true;
	}

	return false;
}

move_cursor_forward :: (using buffer : *Gap_Buffer, clear_selection := true) -> bool
{
	// @Todo (stefan): Handle multibyte characters
	if selection != 0 && clear_selection
	{
		selection = 0;

		return true;
	}

	if cursor < gap_buffer_count (buffer)
	{
		data[cursor] = data[cursor + gap];
		cursor += 1;
		// Update line and column number
		column += 1;
		char := data[cursor - 1];
		if char == #char "\n"
		{
			line  += 1;
			column = 0;
		}

		return true;
	}

	return false;
}

move_cursor_backward :: (using buffer : *Gap_Buffer, clear_selection := true) -> bool
{
	// @Todo (stefan): Handle multibyte characters
	if selection != 0 && clear_selection
	{
		selection = 0;

		return true;
	}

	if cursor > 0
	{
		cursor -= 1;
		data[cursor + gap] = data[cursor];
		// Update line and column numbers
		column -= 1;
		char := data[cursor];
		if char == #char "\n"
		{
			line -= 1;
			column = lines[line] - 1;
		}

		return true;
	}

	return false;
}

move_cursor_to_previous_line :: (using buffer : *Gap_Buffer) -> bool
{
	if line == 0 then return false;

	start_column := column;
	while column != 0
		move_cursor_backward (buffer);

	// At this point, we are at the start of the current line,
	// move to the end of the previous line
	move_cursor_backward (buffer);
	
	while column > start_column
		move_cursor_backward (buffer);

	return true;
}

move_cursor_to_next_line :: (using buffer : *Gap_Buffer) -> bool
{
	if line == lines.count - 1 then return false;

	start_column := column;
	while column != lines[line] - 1
		move_cursor_forward (buffer);

	// At this point, we are at the end of the current line,
	// move to the start of the next line
	move_cursor_forward (buffer);
	
	while column < start_column && !is_at_eol (buffer)
		move_cursor_forward (buffer);

	return true;
}

select_forward :: (using buffer : *Gap_Buffer) -> bool
{
	// @Todo (stefan): Handle multibyte characters
	cached_selection := selection;
	modified := move_cursor_forward (buffer, false);
	if modified then cached_selection -= 1;
	selection = cached_selection;

	return modified;
}

select_backward :: (using buffer : *Gap_Buffer) -> bool
{
	// @Todo (stefan): Handle multibyte characters
	cached_selection := selection;
	modified := move_cursor_backward (buffer, false);
	if modified then cached_selection += 1;
	selection = cached_selection;

	return modified;
}

set_cursor :: (using buffer : *Gap_Buffer, position : s64) -> bool
{
	assert (position >= 0 && position <= gap_buffer_count (buffer), "Invalid cursor position (got % but should be in [0, %]).", position, gap_buffer_count (buffer));

	modified := false;
	if selection != 0
	{
		selection = 0;
		modified  = true;
	}
	
	while cursor < position
	{
		if move_cursor_forward (buffer) then modified = true;
	}

	while cursor > position
	{
		if move_cursor_backward (buffer) then modified = true;
	}

	return modified;
}

is_at_eol :: inline (using buffer : *Gap_Buffer) -> bool #must
{
	if line == lines.count - 1 then return column == lines[line];
	
	return column == lines[line] - 1;
}

gap_buffer_count :: inline (using buffer : *Gap_Buffer) -> s64 #must
{
	return count - gap;
}

gap_buffer_count :: inline (using buffer : Gap_Buffer) -> s64 #must
{
	return count - gap;
}

grow_gap_buffer :: (using buffer : *Gap_Buffer, factor : s64)
{
	back := count - cursor + gap;
	new_gap := gap + count;
	new_count := count * factor + 8;
	new_data := alloc (new_count, allocator, allocator_data);
	memcpy (new_data, data, cursor);
	memcpy (new_data + cursor + new_gap, data + cursor + gap, back);
	
	free (data, allocator, allocator_data);
	data  = new_data;
	count = new_count;
	gap   = new_gap;
}

get_front_part :: inline (using buffer : Gap_Buffer) -> []u8 #must
{
	result : []u8 = ---;
	result.data  = data;
	result.count = cursor;

	return result;
}

get_back_part :: inline (using buffer : Gap_Buffer) -> []u8 #must
{
	result : []u8 = ---;
	result.data  = data + cursor + gap;
	result.count = count - cursor - gap;

	return result;
}

operator [] :: inline (using buffer : Gap_Buffer, position : s64) -> u8
{
	assert (position >= 0 && position < gap_buffer_count (buffer), "Gap buffer bounds check failed: index was %, should be in [0; %].", position, gap_buffer_count (buffer) - 1);
	if position < cursor then return data[position];
	else                      return data[gap + position];
}

for_expansion :: #bake_arguments for_expansion_helper (do_front = true,  do_back = true);
front         :: #bake_arguments for_expansion_helper (do_front = true,  do_back = false);
back          :: #bake_arguments for_expansion_helper (do_front = false, do_back = true);
utf32       :: #bake_arguments utf32_for_expansion_helper (do_front = true,  do_back = true);
utf32_front :: #bake_arguments utf32_for_expansion_helper (do_front = true,  do_back = false);
utf32_back  :: #bake_arguments utf32_for_expansion_helper (do_front = false, do_back = true);

#scope_file

for_expansion_helper :: (using buffer : *Gap_Buffer, body : Code, flags : For_Flags, do_front : bool, do_back : bool) #expand
{
	#assert (do_front || do_back);

	by_pointer :: (flags & .POINTER) == .POINTER;
	reverse    :: (flags & .REVERSE) == .REVERSE;

	#if reverse
	{
		#if do_back  start := gap_buffer_count (buffer) - 1;
		else         start := buffer.cursor - 1;
		#if do_front end := 0;
		else         end := buffer.cursor;
	}
	else
	{
		#if do_front start := 0;
		else         start := buffer.cursor;
		#if do_back  end := gap_buffer_count (buffer) - 1;
		else         end := buffer.cursor - 1;
	}

	#if by_pointer `it : *u8;
	else           `it : u8;

	for <=reverse `it_index : start..end
	{
		it = (<<buffer)[it_index];
		#insert (remove=#assert false "Gap buffer remove while iterating is not yet implemented.") body;
	}
}

utf32_for_expansion_helper :: (using buffer : *Gap_Buffer, body : Code, flags : For_Flags, do_front : bool, do_back : bool) #expand
{
	by_pointer :: (flags & .POINTER) == .POINTER;
	reverse    :: (flags & .REVERSE) == .REVERSE;
	#assert !by_pointer "Gap buffer utf32 iteration cannot be by pointer, because the data does not map 1:1 since it is converted to utf32.";
	#assert !reverse "Gap buffer utf32 reverse iteration is not yet implemented.";

	#if do_front start := 0;
	else         start := buffer.cursor;
	#if do_back  end := gap_buffer_count (buffer);
	else         end := buffer.cursor;
	
	str : string = ---;
	str.data  = data;
	str.count = count;

	// @@ (stefan): Should it_index be the byte offset or the character position in the utf32 string ?
	`it_index := start;
	while it_index < end
	{
		`it, size := utf8_rune_at_byte (str, ifx it_index < cursor then it_index else it_index + gap);
		#insert (remove=#assert false "Gap buffer remove while iterating as utf32 is not yet implemented.", continue={ it_index += xx size; continue; }) body;
		it_index += xx size;
	}
}
