Gap_Buffer :: struct
{
	data : *u32;
	allocated : s64;

	cursor    : s64;
	selection : s64;
	gap       : s64;

	lines : [..]u32;
	line_index, column_index : s64;

	undo_stack       : [..]Text_Operation;
	redo_stack       : [..]Text_Operation;
	undo_redo_buffer : [..]u32;

	allocator      : Allocator;
	allocator_data : *void;
}

Text_Operation :: struct
{
	Kind :: enum
	{
		INSERT;
		BACKSPACE;
		DELETE;
		MOVE_LINE_UP;
		MOVE_LINE_DOWN;
	}

	kind : Kind;
	cursor : s64;
	line_index : s64;
	offset_in_buffer : s64;
}

make_text_operation :: inline (buffer : *Gap_Buffer, kind : Text_Operation.Kind, cursor : s64, line_index : s64) -> Text_Operation #must
{
	result : Text_Operation = ---;
	result.kind             = kind;
	result.cursor           = cursor;
	result.line_index       = line_index;
	result.offset_in_buffer = buffer.undo_redo_buffer.count;
	
	return result;
}

make_text_operation :: inline (using buffer : *Gap_Buffer, kind : Text_Operation.Kind) -> Text_Operation #must
{
	return make_text_operation (buffer, kind, cursor, line_index);
}

operator [] :: inline (using buffer : *Gap_Buffer, position : s64) -> u32 #must
{
	assert (position >= 0 && position < gap_buffer_count (buffer), "Gap buffer index is out of bounds (got %, must be in [%, %]).", position, 0, gap_buffer_count (buffer) - 1);
	if position >= cursor then return data[gap + position];
	else return data[position];
}

gap_buffer_count :: inline (using buffer : *Gap_Buffer) -> s64 #must
{
	return allocated - gap;
}

gap_buffer_count :: inline (using buffer : Gap_Buffer) -> s64 #must
{
	return allocated - gap;
}

get_front_part :: inline (using buffer : Gap_Buffer) -> []u32 #must
{
	result : []u32 = ---;
	result.data  = data;
	result.count = cursor;

	return result;
}

get_back_part :: inline (using buffer : Gap_Buffer) -> []u32 #must
{
	result : []u32 = ---;
	result.data  = data + cursor + gap;
	result.count = allocated - cursor - gap;

	return result;
}

stitch_front_and_back_together :: (buffer : Gap_Buffer, allocator : Allocator, allocator_data := null) -> []u32 #must
{
	front  := get_front_part (buffer);
	back   := get_back_part (buffer);
	result := alloc_array (u32, front.count + back.count, allocator, allocator_data);
	memcpy (result.data, front.data, front.count * size_of (u32));
	memcpy (result.data + front.count, back.data, back.count * size_of (u32));

	return result;
}

is_at_eol :: inline (using buffer : *Gap_Buffer) -> bool #must
{
	if line_index == lines.count - 1 then return column_index == lines[line_index];

	return column_index == lines[line_index] - 1;
}

clone_to_string :: (buffer : Gap_Buffer, eol_sequence : EOL_Sequence, str_allocator : Allocator, str_allocator_data := null) -> string #must
{
	builder := make_string_builder (gap_buffer_count (buffer) + 100, str_allocator, str_allocator_data);
	for codepoint, i : buffer
	{
		utf8_buffer : [4]u8;
		count := utf8_encode (utf8_buffer, codepoint);
		if count == 1 && utf8_buffer[0] == #char "\n" && eol_sequence == .CRLF
			print_char_to_builder (*builder, #char "\r");
		for i : 0..count - 1
			print_char_to_builder (*builder, utf8_buffer[i]);
	}

	return to_string (builder);
}

init_gap_buffer :: (buffer : *Gap_Buffer, capacity : s64, undo_redo_capacity : s64, allocator : Allocator, allocator_data := null)
{
	buffer.data = alloc (size_of (u32) * capacity, allocator, allocator_data);
	buffer.allocated = capacity;

	buffer.cursor    = 0;
	buffer.selection = 0;
	buffer.gap       = capacity;

	buffer.lines        = make_array (u32, 1000, allocator, allocator_data);
	push_to_array (*buffer.lines, 0);
	buffer.line_index   = 0;
	buffer.column_index = 0;

	buffer.undo_stack       = make_array (Text_Operation, undo_redo_capacity, allocator, allocator_data);
	buffer.redo_stack       = make_array (Text_Operation, undo_redo_capacity, allocator, allocator_data);
	buffer.undo_redo_buffer = make_array (u32, undo_redo_capacity * 10, allocator, allocator_data);

	buffer.allocator      = allocator;
	buffer.allocator_data = allocator_data;
}

make_gap_buffer :: (capacity : s64, undo_redo_capacity : s64, allocator : Allocator, allocator_data := null) -> Gap_Buffer #must
{
	result : Gap_Buffer = ---;
	inline init_gap_buffer (*result, capacity, undo_redo_capacity, allocator, allocator_data);

	return result;
}

reset_gap_buffer :: (using buffer : *Gap_Buffer)
{
	free (data, allocator, allocator_data);
	data = null;
	allocated = 0;
	cursor = 0;
	selection = 0;
	gap = 0;
	reset_array (*lines);
	line_index = 0;
	column_index = 0;
	reset_array (*undo_stack);
	reset_array (*redo_stack);
	reset_array (*undo_redo_buffer);
}

clear_gap_buffer :: (using buffer : *Gap_Buffer)
{
	cursor = 0;
	selection = 0;
	gap = allocated;
	clear_array (*lines);
	push_to_array (*lines, 0);
	line_index   = 0;
	column_index = 0;
	clear_undo_redo (buffer);
}

clear_undo_redo :: (using buffer : *Gap_Buffer)
{
	clear_array (*undo_stack);
	clear_array (*redo_stack);
	clear_array (*undo_redo_buffer);
}

clear_redo :: (using buffer : *Gap_Buffer)
{
	if redo_stack.count == 0 then return;

	op := array_top (redo_stack);
	assert (undo_redo_buffer.count >= op.offset_in_buffer);
	undo_redo_buffer.count = op.offset_in_buffer;
	clear_array (*redo_stack);
}

grow_gap_buffer :: (using buffer : *Gap_Buffer, factor : s64)
{
	count := gap_buffer_count (buffer);
	back  := gap_buffer_count (buffer) - cursor;
	new_capacity := allocated * factor + 8;
	new_gap  := new_capacity - count;
	new_data := alloc (new_capacity * size_of (u32), allocator, allocator_data);
	memcpy (new_data, data, cursor * size_of (u32));
	memcpy (new_data + cursor + new_gap, data + cursor + gap, back * size_of (u32));
	
	free (data, allocator, allocator_data);
	data      = new_data;
	allocated = new_capacity;
	gap       = new_gap;
}

move_cursor_forward :: (using buffer : *Gap_Buffer, select := false) -> bool
{
	if !select && selection != 0
	{
		selection = 0;

		return true;
	}
	
	if cursor < gap_buffer_count (buffer)
	{
		next := data[cursor + gap];
		data[cursor] = next;
		cursor += 1;
		if select then selection -= 1;
		column_index += 1;

		if next == #char "\n"
		{
			line_index  += 1;
			column_index = 0;
		}

		return true;
	}

	return false;
}

move_cursor_backward :: (using buffer : *Gap_Buffer, select := false) -> bool
{
	if !select && selection != 0
	{
		selection = 0;

		return true;
	}

	if cursor > 0
	{
		cursor -= 1;
		if select then selection += 1;
		previous := data[cursor];
		data[cursor + gap] = previous;
		column_index -= 1;

		if previous == #char "\n"
		{
			line_index -= 1;
			column_index = lines[line_index] - 1;
		}
		
		return true;
	}

	return false;
}

move_cursor :: inline (using buffer : *Gap_Buffer, position : s64, select := false) -> bool
{
	position = clamp (position, 0, gap_buffer_count (buffer));
	if cursor == position then return false;

	while cursor > position
		move_cursor_backward (buffer, select);

	while cursor < position
		move_cursor_forward (buffer, select);

	return true;
}

move_cursor_to_bol :: inline (using buffer : *Gap_Buffer, select := false) -> bool
{
	if column_index == 0 then return false;
	while column_index > 0
		move_cursor_backward (buffer, select);

	return true;
}

move_cursor_to_eol :: inline (using buffer : *Gap_Buffer, select := false) -> bool
{
	if is_at_eol (buffer) then return false;
	while !is_at_eol (buffer)
		move_cursor_forward (buffer, select);

	return true;
}

move_cursor_to_column :: inline (using buffer : *Gap_Buffer, column : s64, select := false) -> bool
{
	if column_index == column then return false;

	while !is_at_eol (buffer) && column_index < column
		move_cursor_forward (buffer, select);

	while column_index > 0 && column_index > column
		move_cursor_backward (buffer, select);

	return true;
}

move_cursor_to_previous_line :: inline (using buffer : *Gap_Buffer, select := false) -> bool
{
	if line_index == 0 then return move_cursor_to_bol (buffer, select);

	start_column := column_index;
	move_cursor_to_bol (buffer, select);
	move_cursor_backward (buffer, select);
	move_cursor_to_column (buffer, start_column, select);

	return true;
}

move_cursor_to_next_line :: inline (using buffer : *Gap_Buffer, select := false) -> bool
{
	if line_index == lines.count - 1 then return move_cursor_to_eol (buffer, select);

	start_column := column_index;
	move_cursor_to_eol (buffer, select);
	move_cursor_forward (buffer, select);
	move_cursor_to_column (buffer, start_column, select);

	return true;
}

move_cursor_to_line :: inline (using buffer : *Gap_Buffer, line : s64, select := false) -> bool
{
	if line_index == line then return false;

	while line_index > 0 && line_index > line
		move_cursor_to_previous_line (buffer, select);

	while line_index < lines.count - 1 && line_index < line
		move_cursor_to_next_line (buffer, select);

	return true;
}

skip_word_forward :: (using buffer : *Gap_Buffer, select := false, stop_at_word_separators := true) -> bool
{
	if cursor == gap_buffer_count (buffer) then return false;

	modified := false;
	while is_space (data[cursor + gap])
	{
		if move_cursor_forward (buffer, select) then modified = true;
		if is_at_eol (buffer) then return modified;
	}

	first := data[cursor + gap];
	if move_cursor_forward (buffer, select) then modified = true;
	while !is_space (data[cursor + gap])
	{
		if is_alpha_num (first)  && !is_alpha_num (data[cursor + gap]) then break;
		if !is_alpha_num (first) &&  is_alpha_num (data[cursor + gap]) then break;
		if data[cursor + gap] == #char "_" then break;
		if is_at_eol (buffer) then break;

		if move_cursor_forward (buffer, select) then modified = true;
	}

	return modified;
}


skip_word_backward :: (using buffer : *Gap_Buffer, select := false, stop_at_word_separators := true) -> bool
{
	if cursor == 0 then return false;

	modified := false;
	while column_index > 0 && is_space (data[cursor - 1])
	{
		if move_cursor_backward (buffer, select) then modified = true;
	}

	first := data[cursor - 1];
	if move_cursor_backward (buffer, select) then modified = true;
	while column_index > 0 && !is_space (data[cursor - 1])
	{
		if is_alpha_num (first)  && !is_alpha_num (data[cursor - 1]) then break;
		if !is_alpha_num (first) &&  is_alpha_num (data[cursor - 1]) then break;
		if data[cursor + gap] == #char "_" then break;
		
		if move_cursor_backward (buffer, select) then modified = true;
	}

	return modified;
}

#scope_file

split_current_line :: inline (using buffer : *Gap_Buffer)
{
	current     := lines[line_index];
	first_half  := column_index;
	second_half := current - first_half;
	lines[line_index] = xx first_half;
	sorted_insert_to_array (*lines, line_index + 1, xx second_half);
}

merge_current_line_with_next_one :: inline (using buffer : *Gap_Buffer)
{
	if line_index == lines.count - 1 then return;
	lines[line_index] += lines[line_index + 1];
	sorted_remove_from_array (*lines, line_index + 1);
}

#scope_export

Undo_Buffering :: enum
{
	NONE;				// Don't buffer the operation
	PUSH_CHARACTERS;	// Push the characters to the undo_redo_buffer
	PUSH_OPERATION;		// Push a new Text_Operation to the undo_stack AND push the characters to the undo_redo_buffer
}

insert_at_cursor :: (using buffer : *Gap_Buffer, codepoint : u32, undo_buffering := Undo_Buffering.PUSH_OPERATION, $auto_tab := false)
{
	if codepoint == #char "\r" then return;
	if selection != 0 then delete_selection (buffer, undo_buffering);
	if gap == 0 then grow_gap_buffer (buffer, 2);

	if undo_buffering ==
	{
	case .PUSH_OPERATION;
		clear_redo (buffer);
		op := make_text_operation (buffer, .INSERT);
		push_to_array (*undo_stack, op);
		undo_buffering = .PUSH_CHARACTERS;
		#through;

	case .PUSH_CHARACTERS;
		push_to_array (*undo_redo_buffer, codepoint);
	}

	data[cursor] = codepoint;
	cursor += 1;
	gap -= 1;

	lines[line_index] += 1;
	column_index += 1;

	if codepoint == #char "\n"
	{
		split_current_line (buffer);
		line_index += 1;
		column_index = 0;

#if auto_tab
{
		move_cursor_to_previous_line (buffer);
		tab_count := 0;
		for :bol_to_eol codepoint, i : buffer
		{
			if codepoint == #char "\t" then tab_count += 1;
			else break;
		}
		move_cursor_to_next_line (buffer);
		for 1..tab_count
			insert_at_cursor (buffer, #char "\t", undo_buffering);
}
	}
}

insert_at_cursor :: inline (using buffer : *Gap_Buffer, utf32 : []u32, undo_buffering := Undo_Buffering.PUSH_OPERATION, $auto_tab := false)
{
	// @Todo (stefan): auto_tab
	if utf32.count == 0 then return;
	
	if undo_buffering == .PUSH_OPERATION
	{
		clear_redo (buffer);
		op := make_text_operation (buffer, .INSERT);
		push_to_array (*undo_stack, op);
		undo_buffering = .PUSH_CHARACTERS;
	}

	for codepoint, i : utf32
		insert_at_cursor (buffer, codepoint, undo_buffering);
}

insert_at_cursor :: inline (using buffer : *Gap_Buffer, str : string, undo_buffering := Undo_Buffering.PUSH_OPERATION, $auto_tab := false)
{
	if str.count == 0 then return;
	utf32, ok := utf8_string_to_runes (str, temp_allocator);
	if !ok then log_warning ("Gap_Buffer", "insert_at_cursor: UTF8 string wasn't valid.");
	insert_at_cursor (buffer, utf32, undo_buffering, auto_tab);
}

backspace_selection :: (using buffer : *Gap_Buffer, undo_buffering := Undo_Buffering.PUSH_OPERATION) -> bool
{
	if selection != 0 then return delete_selection (buffer, undo_buffering);

	if cursor > 0
	{
		start_cursor     := cursor;
		start_line_index := line_index;

		cursor   -= 1;
		gap      += 1;
		selection = 0;

		lines[line_index] -= 1;
		column_index      -= 1;

		backspaced_char := data[cursor];
		if backspaced_char == #char "\n"
		{
			line_index -= 1;
			column_index = lines[line_index] - 1;
			merge_current_line_with_next_one (buffer);
		}

		if undo_buffering ==
		{
		case .PUSH_OPERATION;
			clear_redo (buffer);
			op := make_text_operation (buffer, .BACKSPACE, start_cursor, start_line_index);
			push_to_array (*undo_stack, op);
			#through;

		case .PUSH_CHARACTERS;
			push_to_array (*undo_redo_buffer, backspaced_char);
		}

		return true;
	}

	return false;
}

delete_selection :: (using buffer : *Gap_Buffer, undo_buffering := Undo_Buffering.PUSH_OPERATION) -> bool
{
	delete_helper :: inline (using buffer : *Gap_Buffer, undo_buffering : Undo_Buffering)
	{
		deleted_char := data[cursor + gap];
		if undo_buffering == .PUSH_CHARACTERS then push_to_array (*undo_redo_buffer, deleted_char);
		gap += 1;
		lines[line_index] -= 1;
		if deleted_char == #char "\n"
			merge_current_line_with_next_one (buffer);
	}

	if cursor < gap_buffer_count (buffer) || selection != 0
	{
		if undo_buffering == .PUSH_OPERATION
		{
			clear_redo (buffer);
			at := ifx selection < 0 then cursor + selection else cursor;
			op := make_text_operation (buffer, .DELETE, at, line_index);
			push_to_array (*undo_stack, op);
			undo_buffering = .PUSH_CHARACTERS;
		}

		if selection == 0
			delete_helper (buffer, undo_buffering);

		while selection < 0
		{
			move_cursor_backward (buffer, select = true);
			delete_helper (buffer, undo_buffering);
		}

		while selection > 0
		{
			selection -= 1;
			delete_helper (buffer, undo_buffering);
		}

		return true;
	}

	return false;
}

move_line_up :: (using buffer : *Gap_Buffer, undo_buffering := Undo_Buffering.PUSH_OPERATION) -> bool
{
	if line_index == 0 then return false;

	if undo_buffering == .PUSH_OPERATION
	{
		clear_redo (buffer);
		op := make_text_operation (buffer, .MOVE_LINE_UP);
		push_to_array (*undo_stack, op);
	}

	line_buffer := make_array (u32, lines[line_index] + 1, temp_allocator);
	start_column_index := column_index;
	is_last_line := line_index == lines.count - 1;
	move_cursor_to_bol (buffer);

	if lines[line_index] != 0
	{
		eol := false;
		while !eol
		{
			eol = is_at_eol (buffer);
			if is_last_line && eol then break;
			push_to_array (*line_buffer, data[cursor + gap]);
			if undo_buffering == .PUSH_CHARACTERS then push_to_array (*undo_redo_buffer, data[cursor + gap]);
			delete_selection (buffer, undo_buffering = .NONE);
		}
	}

	if is_last_line
	{
		// Make sure there is a LF at the end of the line_buffer
		push_to_array (*line_buffer, #char "\n");
		if undo_buffering == .PUSH_CHARACTERS then push_to_array (*undo_redo_buffer, #char "\n");
		// Remove the EOL of the previous line, so it becomes the last line
		backspace_selection (buffer, undo_buffering = .NONE);
		// Start inserting the characters back from the beginning of the line
		move_cursor_to_bol (buffer);
	}
	else
	{
		move_cursor_to_previous_line (buffer);
	}

	insert_at_cursor (buffer, line_buffer, undo_buffering = .NONE);
	// We inserted a EOL sequence, and so we need to go back to the previous line
	move_cursor_to_previous_line (buffer);
	move_cursor_to_column (buffer, start_column_index);

	return true;
}

move_line_down :: (using buffer : *Gap_Buffer, undo_buffering := Undo_Buffering.PUSH_OPERATION) -> bool
{
	if line_index == lines.count - 1 then return false;

	if undo_buffering == .PUSH_OPERATION
	{
		clear_redo (buffer);
		op := make_text_operation (buffer, .MOVE_LINE_DOWN);
		push_to_array (*undo_stack, op);
	}

	line_buffer := make_array (u32, lines[line_index] + 1, temp_allocator);
	start_column_index := column_index;
	move_to_last_line := line_index == lines.count - 2;
	move_cursor_to_bol (buffer);

	eol := false;
	while !eol
	{
		eol = is_at_eol (buffer);
		push_to_array (*line_buffer, data[cursor + gap]);
		if undo_buffering == .PUSH_CHARACTERS then push_to_array (*undo_redo_buffer, data[cursor + gap]);
		delete_selection (buffer, undo_buffering = .NONE);
	}

	if move_to_last_line
	{
		move_cursor_to_eol (buffer);
		insert_at_cursor (buffer, #char "\n", undo_buffering = .NONE);
		pop_from_array (*line_buffer);
		if undo_buffering == .PUSH_CHARACTERS then pop_from_array (*undo_redo_buffer);
	}
	else
	{
		move_cursor_to_next_line (buffer);
	}

	insert_at_cursor (buffer, line_buffer, undo_buffering = .NONE);
	if !move_to_last_line then move_cursor_to_previous_line (buffer);
	move_cursor_to_column (buffer, start_column_index);

	return true;
}

undo_last_operation :: (using buffer : *Gap_Buffer) -> bool
{
	if undo_stack.count == 0 then return false;
	top := undo_redo_buffer.count;
	if redo_stack.count > 0 then top = array_top (redo_stack).offset_in_buffer;
	op := pop_from_array (*undo_stack);
	push_to_array (*redo_stack, op);

	if #complete op.kind ==
	{
	case .INSERT;
		move_cursor (buffer, op.cursor);
		count := top - op.offset_in_buffer;
		for 1..count
			delete_selection (buffer, undo_buffering = .NONE);

	case .BACKSPACE;
		to_insert : []u32 = ---;
		to_insert.data  = undo_redo_buffer.data  + op.offset_in_buffer;
		to_insert.count = top - op.offset_in_buffer;
		move_cursor (buffer, op.cursor - to_insert.count);
		insert_at_cursor (buffer, to_insert, undo_buffering = .NONE);

	case .DELETE;
		to_insert : []u32 = ---;
		to_insert.data  = undo_redo_buffer.data  + op.offset_in_buffer;
		to_insert.count = top - op.offset_in_buffer;
		move_cursor (buffer, op.cursor);
		insert_at_cursor (buffer, to_insert, undo_buffering = .NONE);
		move_cursor (buffer, op.cursor);

	case .MOVE_LINE_UP;
		move_cursor_to_line (buffer, op.line_index - 1);
		move_line_down (buffer, undo_buffering = .NONE);

	case .MOVE_LINE_DOWN;
		move_cursor_to_line (buffer, op.line_index + 1);
		move_line_up (buffer, undo_buffering = .NONE);
	}

	return true;
}

redo_undone_operation :: (using buffer : *Gap_Buffer) -> bool
{
	if redo_stack.count == 0 then return false;
	op := pop_from_array (*redo_stack);
	push_to_array (*undo_stack, op);
	top := undo_redo_buffer.count;
	if redo_stack.count > 0 then top = array_top (redo_stack).offset_in_buffer;

	if #complete op.kind ==
	{
	case .INSERT;
		to_insert : []u32 = ---;
		to_insert.data  = undo_redo_buffer.data  + op.offset_in_buffer;
		to_insert.count = top - op.offset_in_buffer;
		move_cursor (buffer, op.cursor);
		insert_at_cursor (buffer, to_insert, undo_buffering = .NONE);

	case .BACKSPACE;
		count := top - op.offset_in_buffer;
		move_cursor (buffer, op.cursor);
		for 1..count
			backspace_selection (buffer, undo_buffering = .NONE);

	case .DELETE;
		count := top - op.offset_in_buffer;
		move_cursor (buffer, op.cursor);
		for 1..count
			delete_selection (buffer, undo_buffering = .NONE);
	
	case .MOVE_LINE_UP;
		move_cursor_to_line (buffer, op.line_index);
		move_line_up (buffer, undo_buffering = .NONE);

	case .MOVE_LINE_DOWN;
		move_cursor_to_line (buffer, op.line_index);
		move_line_down (buffer, undo_buffering = .NONE);
	}

	return true;
}

for_expansion :: (using buffer : *Gap_Buffer, body : Code, flags : For_Flags) #expand
{
	by_pointer :: (flags & .POINTER) == .POINTER;
	reverse    :: (flags & .REVERSE) == .REVERSE;

#if reverse
{
	start := gap_buffer_count (buffer) - 1;
	end   := 0;
}
else
{
	start := 0;
	end   := gap_buffer_count (buffer) - 1;
}

	#if by_pointer `it : *u32;
	else           `it :  u32;	
	for <=reverse `it_index : start..end
	{
		position := it_index;
		if it_index >= cursor then position += gap;
		#if by_pointer it = *buffer.data[position];
		else           it =  buffer.data[position];
		#insert (remove=#assert false "If you want to remove while iterating, use the moving_cursor for expansion instead.") body;
	}
}

moving_cursor :: (using buffer : *Gap_Buffer, body : Code, flags : For_Flags) #expand
{
	by_pointer :: (flags & .POINTER) == .POINTER;
	reverse    :: (flags & .REVERSE) == .REVERSE;

	start_cursor := cursor;
#if reverse
{
	move_cursor (buffer, gap_buffer_count (buffer) - 1);
	`it_index := gap_buffer_count (buffer) - 1;
	#if by_pointer `it : *u32;
	else           `it :  u32;	
	while cursor > 0
	{
		#if by_pointer it = *buffer.data[cursor + gap];
		else           it =  buffer.data[cursor + gap];
		#insert (remove=delete_selection (buffer), continue={ move_cursor_backward (buffer); continue; }) body;
		move_cursor_backward (buffer);
	}
}
else
{
	move_cursor (buffer, 0);
	`it_index := 0;
	#if by_pointer `it : *u32;
	else           `it :  u32;	
	while cursor < gap_buffer_count (buffer)
	{
		#if by_pointer it = *buffer.data[cursor + gap];
		else           it =  buffer.data[cursor + gap];
		#insert (remove=delete_selection (buffer), continue={ move_cursor_forward (buffer); continue; }) body;
		move_cursor_forward (buffer);
	}
}

	move_cursor (buffer, start_cursor);
}

bol_to_eol :: (using buffer : *Gap_Buffer, body : Code, flags : For_Flags) #expand
{
	by_pointer :: (flags & .POINTER) == .POINTER;
	reverse    :: (flags & .REVERSE) == .REVERSE;

	start_column_index := column_index;
#if reverse
{
	move_cursor_to_eol (buffer);
	#if by_pointer `it : *u32;
	else           `it :  u32;	
	while column_index > 0
	{
		#if by_pointer it = *buffer.data[cursor + gap];
		else           it =  buffer.data[cursor + gap];
		`it_index := column_index;
		#insert (remove=delete_selection (buffer), continue={ move_cursor_backward (buffer); continue; }) body;
		move_cursor_backward (buffer);
	}
}
else
{
	move_cursor_to_bol (buffer);
	#if by_pointer `it : *u32;
	else           `it :  u32;	
	while column_index < lines[line_index] - 1
	{
		#if by_pointer it = *buffer.data[cursor + gap];
		else           it =  buffer.data[cursor + gap];
		`it_index := column_index;
		#insert (remove=delete_selection (buffer), continue={ move_cursor_forward (buffer); continue; }) body;
		move_cursor_forward (buffer);
	}
}

	move_cursor_to_column (buffer, start_column_index);
}

selected_chars :: (using buffer : *Gap_Buffer, body : Code, flags : For_Flags) #expand
{
	by_pointer :: (flags & .POINTER) == .POINTER;
	reverse    :: (flags & .REVERSE) == .REVERSE;

	#if reverse
	{
		start := ifx selection < 0 then cursor - 1 else cursor + selection - 1;
		end   := ifx selection < 0 then cursor + selection else cursor;
	}
	else
	{
		start := ifx selection < 0 then cursor + selection else cursor;
		end   := ifx selection < 0 then cursor - 1 else cursor + selection - 1;
	}

	#if by_pointer `it : *u32;
	else           `it : u32;
	for <=reverse `it_index : start..end
	{
		position := it_index;
		if it_index >= cursor then position += gap;
		#if by_pointer it = *buffer.data[position];
		else           it =  buffer.data[position];
		#insert (remove=#assert false "Gap buffer remove while iterating is not yet implemented.") body;
	}
}
