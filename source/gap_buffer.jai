#import "Circular_Stack";

EOL_Sequence :: enum
{
	LF;
	CRLF;
}

Gap_Buffer :: struct
{
	data   : *u8;
	count  : s64;
	cursor : s64;
	gap    : s64;
	lines  : [..]u32;	// Number of utf32 codepoints for each line
	line_index, column_index : s64;	// Starts at 0
	selection : s64;
	eol_sequence : EOL_Sequence;

	undo_stack : Circular_Stack (Text_Operation);
	redo_stack : Circular_Stack (Text_Operation);

	allocator : Allocator;
	allocator_data : *void;
}

MAX_UNDO :: 5000;

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
	// @Memory @Cleanup (stefan): Currently, this is allocated on the heap. Ideally, we want a single linear buffer
	// for every operation, and each operation has an offset and a count in that shared buffer. We can do this
	// because the data for operation N won't be freed before the data for operation N+1, unless we overflow
	// the circular stack.
	buffer : []u8;
	// Because we obviously don't want to allocate when inserting/deleting a single char (might not be true if we do the shared buffer thing as described above).
	char   : u8;


	/* @Todo
	count : s64;
	union
	{
		data : *u8;
		char : u8;
	};
	*/
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
	buffer.eol_sequence = .LF;
	buffer.line_index   = 0;
	buffer.column_index = 0;
	init_circular_stack (*buffer.undo_stack, MAX_UNDO, allocator, allocator_data);
	init_circular_stack (*buffer.redo_stack, MAX_UNDO, allocator, allocator_data);
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
	eol_sequence = .LF;
	line_index   = 0;
	column_index = 0;
	reset_circular_stack (*undo_stack);
	reset_circular_stack (*redo_stack);
}

clear_gap_buffer :: (using buffer : *Gap_Buffer)
{
	cursor = 0;
	gap    = count;
	clear_array (*lines);
	push_to_array (*buffer.lines, 0);
	eol_sequence = .LF;
	line_index   = 0;
	column_index = 0;
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

detect_eol_sequence :: (using buffer : *Gap_Buffer) -> EOL_Sequence, correct : bool
{
	line := 1;
	previous_char_was_cr := false;
	correct := true;
	for :utf32 codepoint, i : buffer
	{
		if codepoint == #char "\r"
		{
			if line != 1 && eol_sequence != .CRLF
			{
				println ("Inconsistent line endings at line %.", line);
				correct = false;
			}
				
			eol_sequence = .CRLF;
			previous_char_was_cr = true;
		}
		else if codepoint == #char "\n"
		{
			if eol_sequence == .CRLF && !previous_char_was_cr
			{
				println ("Inconsistent line endings at line %.", line);
				correct = false;
			}

			line += 1;
		}
		else if previous_char_was_cr
		{
			println ("Lonely CR character at line %.", line);
		}

		if codepoint != #char "\r" then previous_char_was_cr = false;
	}

	return eol_sequence, correct;
}

#scope_file

split_current_line :: (using buffer : *Gap_Buffer)
{
	current     := lines[line_index];
	first_half  := column_index;
	second_half := current - first_half;
	// Split
	lines[line_index] = xx first_half;
	sorted_insert_to_array (*lines, line_index + 1, xx second_half);
}

merge_current_line_with_next_one :: (using buffer : *Gap_Buffer)
{
	if line_index == lines.count - 1 then return;

	lines[line_index] += lines[line_index + 1];
	sorted_remove_from_array (*lines, line_index + 1);
}

#scope_export

insert_eol_at_cursor :: (using buffer : *Gap_Buffer, buffer_operation := true, $auto_tab := false)
{
	if #complete eol_sequence ==
	{
	case .CRLF; insert_at_cursor (buffer, "\r\n", buffer_operation, auto_tab);
	case .LF;   insert_at_cursor (buffer, "\n",   buffer_operation, auto_tab);
	}
}

insert_at_cursor :: (using buffer : *Gap_Buffer, char : u8, buffer_operation := true, $auto_tab := false)
{
	if char == #char "\r" then assert (!buffer_operation, "Inserting a single CR character and buffering the operation. This is prohibited.");
	if char == #char "\n" && eol_sequence == .CRLF then assert (!buffer_operation, "Inserting a single LF character and buffering the operation. This is prohibited because the EOL is CRLF.");
	if selection != 0 then delete_selection (buffer, buffer_operation);
	if gap == 0 then grow_gap_buffer (buffer, 2);

	if buffer_operation
	{
		clear_redo_stack (buffer);
		op : Text_Operation;
		op.kind       = .INSERT;
		op.cursor     = cursor;
		op.line_index = line_index;
		op.char       = char;
		push_undo_operation (buffer, op);
	}

	data[cursor] = char;
	cursor += 1;
	gap    -= 1;
	
	// Update line cache
	if utf8_is_first_of_sequence (char)
	{
		lines[line_index] += 1;
		column_index += 1;
	}

	// Handle newline
	if char == #char "\n"
	{
		split_current_line (buffer);
		line_index += 1;
		column_index = 0;

#if auto_tab
{
		// Scan current line for leading tabs and insert the same number of tabs at the beginning of the new line
		move_cursor_to_previous_line (buffer);
		leading_tabs := 0;
		for :bol_to_eol codepoint, i : buffer
		{
			if codepoint == #char "\t" then leading_tabs += 1;
			else break;
		}

		move_cursor_to_next_line (buffer);
		for i : 0..leading_tabs - 1
			insert_at_cursor (buffer, #char "\t", buffer_operation);
}
	}
}

insert_at_cursor :: inline (using buffer : *Gap_Buffer, codepoint : u32, buffer_operation := true, $auto_tab := false)
{
	// @Fix (stefan): Buffer only one operation for this, so we only undo one thing.
	utf8 : [4]u8;
	size := utf8_encode (utf8, codepoint);
	for i : 0..size - 1
		insert_at_cursor (buffer, utf8[i], buffer_operation, auto_tab);
}

insert_at_cursor :: inline (using buffer : *Gap_Buffer, str : string, buffer_operation := true, $auto_tab := false)
{
	if str.count == 0 then return;
	if selection != 0 then delete_selection (buffer, buffer_operation);

	if buffer_operation
	{
		clear_redo_stack (buffer);
		op : Text_Operation;
		op.kind       = .INSERT;
		op.cursor     = cursor;
		op.line_index = line_index;
		if str.count > 1
			op.buffer = clone_to_array (str, heap_allocator);
		else
			op.char = str[0];
		push_undo_operation (buffer, op);
	}

	for i : 0..str.count - 1
		insert_at_cursor (buffer, str[i], buffer_operation = false, auto_tab);
}

// @Cleanup (stefan): Get rid of the ugly accumulator thing and find a more elegant solution.
backspace_selection :: (using buffer : *Gap_Buffer, buffer_operation := true, $backspace_crlf := true, accumulator : *[..]u8 = null) -> bool
{
	if selection != 0 then return delete_selection (buffer, buffer_operation);

	if cursor > 0
	{
		start_cursor     := cursor;
		start_line_index := line_index;
		// Handle multibyte characters
		size := 1;
		while cursor - size > 0 && !utf8_is_first_of_sequence (data[cursor - size])
			size += 1;
		assert (size <= 4, "UTF8 sequence size cannot be larger than 4 (got %).", size);

		backspaced_chars : [..]u8;
		if buffer_operation && !accumulator
		{
			accumulator = *backspaced_chars;
			backspaced_chars = make_array (u8, 5, temp_allocator);
		}

		// Update line cache
		lines[line_index] -= 1;
		column_index -= 1;

		for i : 0..size - 1
		{
			cursor -= 1;
			gap    += 1;
			selection = 0;
			
			// Handle newline
			backspaced_char := data[cursor];
			if backspaced_char == #char "\n"
			{
				line_index -= 1;
				column_index = lines[line_index] - 1;
				merge_current_line_with_next_one (buffer);
#if backspace_crlf
{
				if cursor > 0 && data[cursor - 1] == #char "\r" then backspace_selection (buffer, buffer_operation = false, accumulator = accumulator);
}
			}
		}

		if accumulator
		{
			for i : 0..size - 1
				push_to_array (accumulator, data[start_cursor - size + i]);
		}

		if buffer_operation
		{
			clear_redo_stack (buffer);
			op : Text_Operation;
			op.kind       = .BACKSPACE;
			op.cursor     = start_cursor;
			op.line_index = start_line_index;
			if accumulator.count > 1
				op.buffer = clone_array (<<accumulator, heap_allocator);
			else
				op.char = (<<accumulator)[0];
			push_undo_operation (buffer, op);
		}
	}

	return false;
}

// @Cleanup (stefan): Get rid of the ugly accumulator thing and find a more elegant solution.
delete_at_cursor :: (using buffer : *Gap_Buffer, buffer_operation := true, $delete_crlf := true, accumulator : *[..]u8 = null) -> bool
{
	delete_helper :: inline (using buffer : *Gap_Buffer, $delete_crlf : bool, accumulator : *[..]u8)
	{
		// Handle multibyte characters
		deleted_char := data[cursor + gap];
		size := utf8_sequence_size (deleted_char);
		assert (cursor + size <= gap_buffer_count (buffer), "move_cursor_forward: UTF8 character is % bytes, but there is not enough space between the cursor and the end.", size);

		if accumulator
		{
			for i : 0..size - 1
				push_to_array (accumulator, data[cursor + gap + i]);
		}

		gap += size;

		// Update line cache
		lines[line_index] -= 1;
		if deleted_char == #char "\n"
			merge_current_line_with_next_one (buffer);
		
#if delete_crlf
{
		if deleted_char == #char "\r"	// Handle CRLF
			delete_at_cursor (buffer, false, delete_crlf, accumulator);
}
	}

	if cursor < gap_buffer_count (buffer) || selection != 0
	{
		deleted_characters : [..]u8;
		start_cursor     := cursor;
		start_line_index := line_index;
		if !accumulator && buffer_operation
		{
			accumulator = *deleted_characters;
			deleted_characters = make_array (u8, 2, temp_allocator);
		}
		
		if selection <= 0
		{
			delete_helper (buffer, delete_crlf, accumulator);
		}
		else if selection > 0
		{
			selection -= 1;
			delete_helper (buffer, delete_crlf, accumulator);
		}

		if buffer_operation
		{
			clear_redo_stack (buffer);
			op : Text_Operation;
			op.kind       = .DELETE;
			op.cursor     = start_cursor;
			op.line_index = line_index;
			if accumulator.count > 1
				op.buffer = clone_array (<<accumulator, heap_allocator);
			else
				op.char = (<<accumulator)[0];
			push_undo_operation (buffer, op);
		}

		return true;
	}

	return false;
}

delete_selection :: (using buffer : *Gap_Buffer, buffer_operation := true, $delete_crlf := true) -> bool
{
	// @Todo (stefan): Buffer single operation for whole selection
	if cursor < gap_buffer_count (buffer) || selection != 0
	{
		if selection == 0
		{
			delete_at_cursor (buffer, buffer_operation, delete_crlf);
		}
		else
		{
			if buffer_operation
			{
				clear_redo_stack (buffer);
				op : Text_Operation;
				op.kind       = .DELETE;
				op.cursor     = ifx selection < 0 then cursor + selection else cursor;
				op.line_index = line_index;
				selected := make_array (u8, abs (selection), heap_allocator);
				for :selected_chars char, i : buffer
					push_to_array (*selected, char);
				op.buffer     = selected;
				push_undo_operation (buffer, op);
			}

			while selection < 0
			{
				select_backward (buffer);
				delete_at_cursor (buffer, false, delete_crlf, null);
			}

			while selection > 0
			{
				delete_at_cursor (buffer, false, delete_crlf, null);
			}
		}

		return true;
	}

	return false;
}

move_cursor_forward :: (using buffer : *Gap_Buffer, clear_selection := true, $skip_crlf := true) -> bool, bytes_skipped : s64
{
	if selection != 0 && clear_selection
	{
		selection = 0;

		return true, 0;
	}

	if cursor < gap_buffer_count (buffer)
	{
		// Handle multibyte characters
		char := data[cursor + gap];
		size := utf8_sequence_size (char);
		assert (cursor + size <= gap_buffer_count (buffer), "move_cursor_forward: UTF8 character is % bytes, but there is not enough space between the cursor and the end.", size);
		column_index += 1;
	
		for i : 0..size - 1
		{
			data[cursor] = data[cursor + gap];
			cursor += 1;
		}

		// Update line and column_index number
		if char == #char "\n"
		{
			line_index  += 1;
			column_index = 0;
		}
#if skip_crlf
{
		if char == #char "\r"	// Handle CRLF
		{
			_, skipped := move_cursor_forward (buffer, clear_selection, skip_crlf);
			size += skipped;
		}
}

		return true, size;
	}

	return false, 0;
}

move_cursor_backward :: (using buffer : *Gap_Buffer, clear_selection := true, $skip_crlf := true) -> bool, bytes_skipped : s64
{
	if selection != 0 && clear_selection
	{
		selection = 0;

		return true, 0;
	}

	if cursor > 0
	{
		// Handle multibyte characters
		char := data[cursor];
		size := 1;
		while cursor - size > 0 && !utf8_is_first_of_sequence (data[cursor - size])  size += 1;
		column_index -= 1;

		for i : 0..size - 1
		{
			cursor -= 1;
			data[cursor + gap] = data[cursor];
		}

		// Update line and column_index numbers
		current_char := data[cursor];
		if current_char == #char "\n"
		{
			line_index -= 1;
			column_index = lines[line_index] - 1;
#if skip_crlf
{
			// Handle CRLF
			if cursor > 0 && data[cursor - 1] == #char "\r"
			{
				_, skipped := move_cursor_backward (buffer, clear_selection, skip_crlf);
				size += skipped;
			}
}
		}

		return true, size;
	}

	return false, 0;
}

skip_word_forward :: (using buffer : *Gap_Buffer, select := false) -> bool
{
	if cursor < gap_buffer_count (buffer)
	{
		char := data[cursor + gap];
		if select then select_forward (buffer);
		else move_cursor_forward (buffer);

		if is_space (char)
		{
			while cursor < gap_buffer_count (buffer) && is_space (data[cursor + gap])
			{
				if select then select_forward (buffer);
				else move_cursor_forward (buffer);
			}
		}

		while cursor < gap_buffer_count (buffer) && !is_space (data[cursor + gap])
		{
			if select then select_forward (buffer);
			else move_cursor_forward (buffer);
		}

		return true;
	}

	return false;
}

skip_word_backward :: (using buffer : *Gap_Buffer, select := false) -> bool
{
	if cursor > 0
	{
		char := data[cursor];
		if select then select_backward (buffer);
		else move_cursor_backward (buffer);
		
		if is_space (char)
		{
			while cursor > 0 && is_space (data[cursor])
			{
				if select then select_backward (buffer);
				else move_cursor_backward (buffer);
			}
		}

		while cursor > 0 && !is_space (data[cursor])
		{
			if select then select_backward (buffer);
			else move_cursor_backward (buffer);
		}

		return true;
	}

	return false;
}

move_line_up :: (using buffer : *Gap_Buffer, buffer_operation := true) -> bool
{
	if line_index == 0 then return false;

	if buffer_operation
	{
		clear_redo_stack (buffer);
		op : Text_Operation;
		op.kind       = .MOVE_LINE_UP;
		op.cursor     = cursor;
		op.line_index = line_index;
		push_undo_operation (buffer, op);
	}

	// Strategy:
	// * Save the current line into a buffer while deleting all the characters,
	// * Move the cursor up,
	// * Insert all characters back,
	// * Move the cursor up again
	line_buffer := make_array (u8, lines[line_index] + 10, temp_allocator);
	start_column_index := column_index;
	is_last_line := line_index == lines.count - 1;
	move_cursor_to_bol (buffer);
	
	if lines[line_index] != 0
	{
		eol := false;
		while !eol
		{
			eol = is_at_eol (buffer, ignore_cr = true);
			if is_last_line && eol then break;
			push_to_array (*line_buffer, data[cursor + gap]);
			delete_selection (buffer, buffer_operation = false, delete_crlf = false);
		}
	}

	if is_last_line
	{
		if eol_sequence == .CRLF then push_to_array (*line_buffer, #char "\r");
		push_to_array (*line_buffer, #char "\n");
		// Remove the EOL of the previous line, so it becomes the last line
		backspace_selection (buffer, buffer_operation = false);
		// Start inserting the characters back from the beginning of the line
		move_cursor_to_bol (buffer);
	}
	else
	{
		move_cursor_to_previous_line (buffer);
	}

	for char, i : line_buffer
		insert_at_cursor (buffer, char, buffer_operation = false, auto_tab = false);

	// We inserted a EOL sequence, and so we need to go back to the previous line
	move_cursor_to_previous_line (buffer);
	move_cursor_to_column (buffer, start_column_index);

	return true;
}

move_line_down :: (using buffer : *Gap_Buffer, buffer_operation := true) -> bool
{
	if line_index == lines.count - 1 then return false;

	if buffer_operation
	{
		clear_redo_stack (buffer);
		op : Text_Operation;
		op.kind       = .MOVE_LINE_DOWN;
		op.cursor     = cursor;
		op.line_index = line_index;
		push_undo_operation (buffer, op);
	}

	// Strategy:
	// * Save the current line into a buffer while deleting all the characters,
	// * Move the cursor down,
	// * Insert all characters back,
	// * Move the cursor up
	line_buffer := make_array (u8, lines[line_index] + 10, temp_allocator);
	start_column_index := column_index;
	move_to_last_line := line_index == lines.count - 2;
	move_cursor_to_bol (buffer);
	
	eol := false;
	while !eol
	{
		eol = is_at_eol (buffer, ignore_cr = true);
		push_to_array (*line_buffer, data[cursor + gap]);
		delete_selection (buffer, buffer_operation = false, delete_crlf = false);
	}

	if move_to_last_line
	{
		move_cursor_to_eol (buffer);
		insert_eol_at_cursor (buffer, buffer_operation = false, auto_tab = false);
		pop_from_array (*line_buffer);
	}
	else
	{
		move_cursor_to_next_line (buffer);
	}

	for char, i : line_buffer
		insert_at_cursor (buffer, char, buffer_operation = false, auto_tab = false);

	if !move_to_last_line then move_cursor_to_previous_line (buffer);
	move_cursor_to_column (buffer, start_column_index);

	return true;
}

move_cursor_to_column :: (using buffer : *Gap_Buffer, column : s64, select := false) -> bool
{
	if column_index == column then return false;

	while column_index < column && !is_at_eol (buffer)
	{
		if select then select_forward (buffer);
		else move_cursor_forward (buffer);
	}

	while column_index > column && column_index > 0
	{
		if select then select_backward (buffer);
		else move_cursor_backward (buffer);
	}

	return true;
}

move_cursor_to_previous_line :: (using buffer : *Gap_Buffer, select := false) -> bool
{
	if line_index == 0 then return move_cursor_to_bol (buffer);

	start_column_index := column_index;
	move_cursor_to_bol (buffer, select);
	if select then select_backward (buffer);
	else move_cursor_backward (buffer);
	move_cursor_to_column (buffer, start_column_index, select);

	return true;
}

move_cursor_to_next_line :: (using buffer : *Gap_Buffer, select := false) -> bool
{
	if line_index == lines.count - 1 then return move_cursor_to_eol (buffer);
	
	start_column_index := column_index;
	move_cursor_to_eol (buffer, select);
	if select then select_forward (buffer);
	else move_cursor_forward (buffer);
	move_cursor_to_column (buffer, start_column_index, select);

	return true;
}

move_cursor_to_line :: (using buffer : *Gap_Buffer, line : s64, select := false) -> bool
{
	line = clamp (line, 0, lines.count - 1);
	if line_index == line then return false;

	while line_index < line
		move_cursor_to_next_line (buffer, select);
	while line_index > line
		move_cursor_to_previous_line (buffer, select);

	return true;
}

move_cursor_to_bol :: (using buffer : *Gap_Buffer, select := false) -> bool
{
	moved := false;
	while column_index > 0
	{
		if select
		{
			if select_backward (buffer) then moved = true;
		}
		else
		{
			if move_cursor_backward (buffer) then moved = true;
		}
	}

	return moved;
}

move_cursor_to_eol :: (using buffer : *Gap_Buffer, select := false) -> bool
{
	moved := false;
	while !is_at_eol (buffer)
	{
		if select
		{
			if select_forward (buffer) then moved = true;
		}
		else
		{
			if move_cursor_forward (buffer) then moved = true;
		}
	}

	return moved;
}

// @Todo (stefan): Unify move_cursor_forward and select_forward.
select_forward :: (using buffer : *Gap_Buffer, $skip_crlf := true) -> bool
{
	cached_selection := selection;
	modified, bytes_skipped := move_cursor_forward (buffer, false, skip_crlf);
	if modified then cached_selection -= bytes_skipped;
	selection = cached_selection;

	return modified;
}

// @Todo (stefan): Unify move_cursor_backward and select_backward.
select_backward :: (using buffer : *Gap_Buffer, $skip_crlf := true) -> bool
{
	cached_selection := selection;
	modified, bytes_skipped := move_cursor_backward (buffer, false, skip_crlf);
	if modified then cached_selection += bytes_skipped;
	selection = cached_selection;

	return modified;
}

push_undo_operation :: (using buffer : *Gap_Buffer, op : Text_Operation)
{
	overwrote, overwritten := push_to_stack (*undo_stack, op);
	if overwrote then free (overwritten.buffer, heap_allocator);
}

push_redo_operation :: (using buffer : *Gap_Buffer, op : Text_Operation)
{
	overwrote, overwritten := push_to_stack (*redo_stack, op);
	if overwrote then free (overwritten.buffer, heap_allocator);
}

clear_undo_stack :: inline (using buffer : *Gap_Buffer)
{
	while !is_empty (undo_stack)
	{
		op := pop_from_stack (*undo_stack);
		free (op.buffer, heap_allocator);
	}
}

clear_redo_stack :: inline (using buffer : *Gap_Buffer)
{
	while !is_empty (redo_stack)
	{
		op := pop_from_stack (*redo_stack);
		free (op.buffer, heap_allocator);
	}
}

undo_operation :: (using buffer : *Gap_Buffer) -> bool
{
	if is_empty (undo_stack) then return false;
	op := pop_from_stack (*undo_stack);
	push_redo_operation (buffer, op);

	if #complete op.kind ==
	{
	case .INSERT;
		set_cursor (buffer, op.cursor);
		if op.buffer.count != 0
		{
			for 0..op.buffer.count - 1
				delete_at_cursor (buffer, buffer_operation = false, delete_crlf = false);
		}
		else
		{
			delete_at_cursor (buffer, buffer_operation = false, delete_crlf = false);
		}

	case .BACKSPACE;
		size := op.buffer.count;
		if size == 0 then size = 1;
		set_cursor (buffer, op.cursor - size);
		if op.buffer.count != 0
			insert_at_cursor (buffer, to_string (op.buffer), buffer_operation = false, auto_tab = false);
		else
			insert_at_cursor (buffer, op.char, buffer_operation = false, auto_tab = false);

	case .DELETE;
		set_cursor (buffer, op.cursor);
		if op.buffer.count != 0
			insert_at_cursor (buffer, to_string (op.buffer), buffer_operation = false, auto_tab = false);
		else
			insert_at_cursor (buffer, op.char, buffer_operation = false, auto_tab = false);

	case .MOVE_LINE_UP;
		move_cursor_to_line (buffer, op.line_index - 1);
		move_line_down (buffer, buffer_operation = false);

	case .MOVE_LINE_DOWN;
		move_cursor_to_line (buffer, op.line_index + 1);
		move_line_up (buffer, buffer_operation = false);
	}

	return true;
}

redo_operation :: (using buffer : *Gap_Buffer) -> bool
{
	if is_empty (redo_stack) then return false;
	op := pop_from_stack (*redo_stack);
	push_undo_operation (buffer, op);

	if #complete op.kind ==
	{
	case .INSERT;
		set_cursor (buffer, op.cursor);
		if op.buffer.count != 0
			insert_at_cursor (buffer, to_string (op.buffer), buffer_operation = false, auto_tab = false);
		else
			insert_at_cursor (buffer, op.char, buffer_operation = false, auto_tab = false);

	case .BACKSPACE;
		set_cursor (buffer, op.cursor);
		if op.buffer.count != 0
		{
			for 0..op.buffer.count - 1
				backspace_selection (buffer, buffer_operation = false, backspace_crlf = false);
		}
		else
		{
			backspace_selection (buffer, buffer_operation = false, backspace_crlf = false);
		}

	case .DELETE;
		set_cursor (buffer, op.cursor);
		if op.buffer.count != 0
		{
			for 0..op.buffer.count - 1
				delete_at_cursor (buffer, buffer_operation = false, delete_crlf = false);
		}
		else
		{
			delete_at_cursor (buffer, buffer_operation = false, delete_crlf = false);
		}

	case .MOVE_LINE_UP;
		move_cursor_to_line (buffer, op.line_index);
		move_line_up (buffer, buffer_operation = false);

	case .MOVE_LINE_DOWN;
		move_cursor_to_line (buffer, op.line_index);
		move_line_down (buffer, buffer_operation = false);
	}

	return true;
}

set_cursor :: (using buffer : *Gap_Buffer, position : s64) -> bool
{
	assert (position >= 0 && position <= gap_buffer_count (buffer), "Invalid cursor position (got % but should be in [0, %]).", position, gap_buffer_count (buffer));

	modified := selection != 0 || cursor != position;
	if selection != 0 then selection = 0;

	while cursor < position
		move_cursor_forward (buffer);

	while cursor > position
		move_cursor_backward (buffer);

	return modified;
}

is_at_eol :: inline (using buffer : *Gap_Buffer, $ignore_cr := false) -> bool #must
{
	if line_index == lines.count - 1 then return column_index == lines[line_index];
#if !ignore_cr
{
	if column_index == lines[line_index] - 2 then return data[cursor + gap] == #char "\r";
}

	return column_index == lines[line_index] - 1;
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
	char_count := gap_buffer_count (buffer);
	back := gap_buffer_count (buffer) - cursor;
	new_count := count * factor + 8;
	new_gap := new_count - char_count;
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
		#if by_pointer it = *(<<buffer)[it_index];
		else           it = (<<buffer)[it_index];
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

#scope_export

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

	#if by_pointer `it : *u8;
	else           `it : u8;

	for <=reverse `it_index : start..end
	{
		#if by_pointer it = *(<<buffer)[it_index];
		else           it = (<<buffer)[it_index];
		#insert (remove=#assert false "Gap buffer remove while iterating is not yet implemented.") body;
	}
}

bol_to_eol :: (using buffer : *Gap_Buffer, body : Code, flags : For_Flags) #expand
{
	by_pointer :: (flags & .POINTER) == .POINTER;
	reverse    :: (flags & .REVERSE) == .REVERSE;
	#assert !by_pointer "Gap buffer line iteration cannot be by pointer, because the data does not map 1:1 since it is converted to utf32.";
	#assert !reverse "Gap buffer line reverse iteration is not yet implemented.";

	str : string = ---;
	str.data  = data;
	str.count = count;
	start_column_index := column_index;
	move_cursor_to_bol (buffer);
	while !is_at_eol (buffer)
	{
		`it := utf8_rune_at_byte (str, cursor + gap);
		`it_index := column_index;
		#insert (remove=#assert false "Gap buffer remove while iterating line is not yet implemented.") body;
		move_cursor_forward (buffer);
	}
	move_cursor_to_column (buffer, start_column_index);
}
