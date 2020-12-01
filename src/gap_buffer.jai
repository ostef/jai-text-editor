#import "File";
#import "Windows";

DEFAULT_UNDO_REDO_CAPACITY :: 10_000;

Gap_Buffer :: struct
{
	data   : *Rune;
	count  : s64;
	cursor : int;
	gap    : int;
	selection   : int;
	undo_buffer : Circular_Stack (Operation);
	redo_buffer : Circular_Stack (Operation);

	allocator      : Allocator;
	allocator_data : *void;

	Operation :: struct
	{
		Type :: enum
		{
			INSERT;
			BACKSPACE;
			DELETE;
			BATCH_BEGIN;
			BATCH_END;
		}

		type   : Type;
		cursor : int;
		rune   : Rune;
	}
}

Gap_Buffer_Operation      :: Gap_Buffer.Operation;
Gap_Buffer_Operation_Type :: Gap_Buffer_Operation.Type;

make_gap_buffer :: inline (capacity : int, undo_redo_capacity := DEFAULT_UNDO_REDO_CAPACITY, allocator : Allocator = null, allocator_data := null) -> Gap_Buffer #must
{
	result : Gap_Buffer;
	data := NewArray (capacity, Rune, allocator = allocator, allocator_data = allocator_data);
	result.data     = data.data;
	result.count    = data.count;
	result.gap      = capacity;
	result.allocator      = allocator;
	result.allocator_data = allocator_data;
	result.undo_buffer = make_circular_stack (Gap_Buffer_Operation, undo_redo_capacity, allocator = allocator, allocator_data = allocator_data);
	result.redo_buffer = make_circular_stack (Gap_Buffer_Operation, undo_redo_capacity, allocator = allocator, allocator_data = allocator_data);

	return result;
}

load_file :: inline (using buffer : *Gap_Buffer, filepath : string) -> bool
{
	file_data, ok := read_entire_file (filepath);
	if !ok  return false;
	defer free (file_data);
	
	i := 0;
	newlines := 0;
	while i < file_data.count
	{
		codepoint, size := utf8_rune_at_byte (file_data, xx i);
		if codepoint != #char "\r" insert (buffer, codepoint, buffer_operation = false);	// Ignore freaking '\r'
		i += xx size;
	}

	return true;
}

destroy_gap_buffer :: inline (using buffer : *Gap_Buffer)
{
	destroy_circular_stack (*undo_buffer);
	destroy_circular_stack (*redo_buffer);
	free (data, allocator = allocator, allocator_data = allocator_data);
	count = 0;
	cursor     = 0;
	gap        = 0;
}

insert :: inline (using buffer : *Gap_Buffer, codepoint : Rune, buffer_operation := true)
{
	if gap == 0  gap_buffer_grow (buffer, 2);
	
	if selection != 0  delete (buffer);
	if buffer_operation
	{
		reset (*redo_buffer);
		op : Gap_Buffer_Operation;
		op.type   = .INSERT;
		op.cursor = cursor;
		op.rune   = codepoint;
		push (*undo_buffer, op);
	}

	data[cursor] = codepoint;
	cursor      += 1;
	gap         -= 1;
}

backspace :: inline (using buffer : *Gap_Buffer, buffer_operation := true) -> bool
{
	if selection != 0  return delete (buffer, buffer_operation);

	if cursor > 0
	{
		if buffer_operation
		{
			reset (*redo_buffer);
			op : Gap_Buffer_Operation;
			op.type   = .BACKSPACE;
			op.cursor = cursor - 1;
			op.rune   = (<<buffer)[cursor - 1];
			push (*undo_buffer, op);
		}

		cursor -= 1;
		gap    += 1;
		selection = 0;

		return true;
	}

	return false;
}

delete :: inline (using buffer : *Gap_Buffer, buffer_operation := true) -> bool
{
	delete_helper :: inline (using buffer : *Gap_Buffer, buffer_operation := true)
	{
		if buffer_operation
		{
			reset (*redo_buffer);
			op : Gap_Buffer_Operation;
			op.type   = .DELETE;
			op.cursor = cursor;
			op.rune   = (<<buffer)[cursor];
			push (*undo_buffer, op);
		}

		gap += 1;
	}

	if cursor < gap_buffer_count (buffer) || selection != 0
	{
		if selection != 0
		{
			op : Gap_Buffer_Operation;
			op.type = .BATCH_BEGIN;
			if buffer_operation  push (*undo_buffer, op);

			while selection != 0
			{
				if selection < 0
				{
					select_backward (buffer);
					delete_helper (buffer, buffer_operation);
				}
				else
				{
					selection -= 1;
					delete_helper (buffer, buffer_operation);
				}
			}

			op.type = .BATCH_END;
			if buffer_operation  push (*undo_buffer, op);
		}
		else
		{
			delete_helper (buffer, buffer_operation);
		}

		return true;
	}

	return false;
}

backspace_word :: inline (using buffer : *Gap_Buffer) -> bool
{
	op : Gap_Buffer_Operation;
	op.type = .BATCH_BEGIN;
	push (*undo_buffer, op);

	modified := backspace (buffer);
	
	while cursor > 0 && is_space ((<<buffer)[cursor - 1]) && (<<buffer)[cursor - 1] != #char "\n"
	{
		if backspace (buffer)  modified = true;
	}

	while cursor > 0 && is_alpha_num ((<<buffer)[cursor - 1])
	{
		if backspace (buffer)  modified = true;
	}
	
	op.type = .BATCH_END;
	push (*undo_buffer, op);

	return modified;
}

delete_word :: inline (using buffer : *Gap_Buffer) -> bool
{
	op : Gap_Buffer_Operation;
	op.type = .BATCH_BEGIN;
	push (*undo_buffer, op);

	modified := delete (buffer);
	
	while cursor < gap_buffer_count (buffer) && is_space ((<<buffer)[cursor]) && (<<buffer)[cursor] != #char "\n"
	{
		if delete (buffer)  modified = true;
	}

	while cursor < gap_buffer_count (buffer) && is_alpha_num ((<<buffer)[cursor])
	{
		if delete (buffer)  modified = true;
	}

	op.type = .BATCH_END;
	push (*undo_buffer, op);

	return modified;
}

move_cursor_forward :: inline (using buffer : *Gap_Buffer, clear_selection := true) -> bool
{
	modified := false;
	if selection != 0 && clear_selection
	{
		selection = 0;
		modified = true;
	}

	if cursor < gap_buffer_count (buffer)
	{
		data[cursor] = data[cursor + gap];
		cursor      += 1;
		modified     = true;
	}

	return modified;
}

move_cursor_backward :: inline (using buffer : *Gap_Buffer, clear_selection := true) -> bool
{
	modified := false;
	if selection != 0 && clear_selection
	{
		selection = 0;
		modified = true;
	}

	if cursor > 0
	{
		data[cursor + gap - 1] = data[cursor - 1];
		cursor -= 1;
		modified = true;
	}

	return modified;
}


set_cursor :: inline (using buffer : *Gap_Buffer, new_cursor : int) -> bool
{
	assert (new_cursor >= 0 && new_cursor <= gap_buffer_count (buffer), "Cursor is %, should be in [0; %]", new_cursor, gap_buffer_count (buffer));
	// @Cleanup (stefan): This is not the fastest implementation.
	modified : bool;
	
	if selection != 0
	{
		selection = 0;
		modified = true;
	}

	while cursor < new_cursor  { if move_cursor_forward  (buffer)  modified = true; }
	while cursor > new_cursor  { if move_cursor_backward (buffer)  modified = true; }

	return modified;
}

skip_word_forward :: inline (using buffer : *Gap_Buffer) -> int
{
	cached_cursor := cursor;
	move_cursor_forward (buffer);
	
	while cursor < gap_buffer_count (buffer) && is_space ((<<buffer)[cursor]) && (<<buffer)[cursor] != #char "\n"
	{
		move_cursor_forward (buffer);
	}

	while cursor < gap_buffer_count (buffer) && is_alpha_num ((<<buffer)[cursor])
	{
		move_cursor_forward (buffer);
	}

	return cursor - cached_cursor;
}

skip_word_backward :: inline (using buffer : *Gap_Buffer) -> int
{
	cached_cursor := cursor;
	move_cursor_backward (buffer);
	
	while cursor > 0 && is_space ((<<buffer)[cursor - 1]) && (<<buffer)[cursor - 1] != #char "\n"
	{
		move_cursor_backward (buffer);
	}

	while cursor > 0 && is_alpha_num ((<<buffer)[cursor - 1])
	{
		move_cursor_backward (buffer);
	}

	return cursor - cached_cursor;
}

select_forward :: inline (using buffer : *Gap_Buffer) -> bool
{
	cached_selection := selection;
	modified := move_cursor_forward (buffer, false);
	if modified  cached_selection -= 1;
	selection = cached_selection;

	return modified;
}

select_backward :: inline (using buffer : *Gap_Buffer) -> bool
{
	cached_selection := selection;
	modified := move_cursor_backward (buffer, false);
	if modified  cached_selection += 1;
	selection = cached_selection;

	return modified;
}

select_to :: inline (using buffer : *Gap_Buffer, new_cursor : int) -> bool
{
	assert (new_cursor >= 0 && new_cursor <= gap_buffer_count (buffer), "Cursor is %, should be in [0; %]", new_cursor, gap_buffer_count (buffer));
	// @Cleanup (stefan): This is not the fastest implementation.
	modified : bool;
	while cursor < new_cursor  { if select_forward  (buffer)  modified = true; }
	while cursor > new_cursor  { if select_backward (buffer)  modified = true; }

	return modified;
}

select_word_forward :: inline (using buffer : *Gap_Buffer) -> int
{
	cached_cursor := cursor;
	select_forward (buffer);
	
	while cursor < gap_buffer_count (buffer) && is_space ((<<buffer)[cursor]) && (<<buffer)[cursor] != #char "\n"
	{
		select_forward (buffer);
	}

	while cursor < gap_buffer_count (buffer) && is_alpha_num ((<<buffer)[cursor])
	{
		select_forward (buffer);
	}

	return cursor - cached_cursor;
}

select_word_backward :: inline (using buffer : *Gap_Buffer) -> int
{
	cached_cursor := cursor;
	select_backward (buffer);

	while cursor > 0 && is_space ((<<buffer)[cursor - 1]) && (<<buffer)[cursor - 1] != #char "\n"
	{
		select_backward (buffer);
	}

	while cursor > 0 && is_alpha_num ((<<buffer)[cursor - 1])
	{
		select_backward (buffer);
	}

	return cursor - cached_cursor;
}

undo_operation :: (using buffer : *Gap_Buffer) -> bool
{
	perform_undo_for_single_operation :: (buffer : *Gap_Buffer, op : Gap_Buffer_Operation)
	{
		if op.type ==
		{
		case .INSERT;
			set_cursor (buffer, op.cursor);
			delete (buffer, false);

		case .BACKSPACE;
			set_cursor (buffer, op.cursor);
			insert (buffer, op.rune, false);

		case .DELETE;
			set_cursor (buffer, op.cursor);
			insert (buffer, op.rune, false);
			move_cursor_backward (buffer);
		}
	}

	if is_empty (undo_buffer)  return false;
	op := pop (*undo_buffer);
	push (*redo_buffer, op);

	if op.type == .BATCH_END
	{
		op = pop (*undo_buffer);
		push (*redo_buffer, op);
		
		while op.type != .BATCH_BEGIN && !is_empty (undo_buffer)
		{
			perform_undo_for_single_operation (buffer, op);
			op = pop (*undo_buffer);
			push (*redo_buffer, op);
		}
	}
	else
	{
		perform_undo_for_single_operation (buffer, op);
	}

	return true;
}

redo_operation :: (using buffer : *Gap_Buffer) -> bool
{
	perform_redo_for_single_operation :: (buffer : *Gap_Buffer, op : Gap_Buffer_Operation)
	{
		if op.type ==
		{
		case .INSERT;
			set_cursor (buffer, op.cursor);
			insert (buffer, op.rune, false);

		case .BACKSPACE;
			set_cursor (buffer, op.cursor);
			delete (buffer, false);

		case .DELETE;
			set_cursor (buffer, op.cursor);
			delete (buffer, false);
		}
	}

	if is_empty (redo_buffer)  return false;
	op := pop (*redo_buffer);
	push (*undo_buffer, op);

	if op.type == .BATCH_BEGIN
	{
		op = pop (*redo_buffer);
		push (*undo_buffer, op);

		while op.type != .BATCH_END && !is_empty (redo_buffer)
		{
			perform_redo_for_single_operation (buffer, op);
			op = pop (*redo_buffer);
			push (*undo_buffer, op);
		}
	}
	else
	{
		perform_redo_for_single_operation (buffer, op);
	}

	return true;
}

gap_buffer_count :: inline (using buffer : *Gap_Buffer) -> int
{
	return count - gap;
}

gap_buffer_count :: inline (using buffer : Gap_Buffer) -> int
{
	return count - gap;
}

gap_buffer_grow :: (using buffer : *Gap_Buffer, factor : int)
{
	back    := count - cursor + gap;
	new_gap := gap + count;
	new_data     := NewArray (count * 2, Rune, allocator = allocator, allocator_data = allocator_data);
	memcpy (new_data.data, data, size_of (Rune) * cursor);
	memset (new_data.data + cursor, 1, size_of (Rune) * new_gap);		// Is this necessary ??
	memcpy (new_data.data + cursor + new_gap, data + cursor + gap, size_of (Rune) * back);
	
	free (data, allocator = allocator, allocator_data = allocator_data);
	data  = new_data.data;
	count = new_data.count;
	gap   = new_gap;
}

get_front_part :: (using buffer : *Gap_Buffer) -> []Rune
{
	result : []Rune;
	result.data = data;
	result.count = cursor;

	return result;
}

get_back_part :: (using buffer : *Gap_Buffer) -> []Rune
{
	result : []Rune;
	result.data = data + cursor + gap;
	result.count = count - cursor - gap;

	return result;
}

write_gap_buffer_to_file :: (using buffer : *Gap_Buffer, filepath : string) -> bool
{
	file, ok := file_open (filepath, for_writing = true);
	if !ok
	{
		err := GetLastError ();
		println ("write_gap_buffer_to_file: Error: %", err);

		return false;
	}

	defer file_close (*file);

	front := get_front_part (buffer);
	back  := get_back_part  (buffer);
	str, valid := utf8_runes_to_string (front, allocator = __temporary_allocator);
	
	if !valid
	{
		println ("write_gap_buffer_to_file: Could not convert buffer to utf8 string");

		return false;
	}
	
	file_write (*file, str.data, str.count);
	str, valid  = utf8_runes_to_string (back,  allocator = __temporary_allocator);
	
	if !valid
	{
		println ("write_gap_buffer_to_file: Could not convert buffer to utf8 string");

		return false;
	}
	
	file_write (*file, str.data, str.count);

	return true;
}

operator [] :: inline (using buffer : Gap_Buffer, index : int) -> Rune
{
	assert (index >= 0 && index < gap_buffer_count (buffer), "Bounds check failed: index was %, should be in range [0; %]", index, gap_buffer_count (buffer) - 1);
	if index < cursor   return data[index];
	else                return data[gap + index];
}

for_expansion :: #bake_arguments for_expansion_helper (do_front = true,  do_back = true);
front         :: #bake_arguments for_expansion_helper (do_front = true,  do_back = false);
back          :: #bake_arguments for_expansion_helper (do_front = false, do_back = true);

#scope_file

for_expansion_helper :: (buffer : *Gap_Buffer, body : Code, by_pointer : bool, reverse : bool, do_front : bool, do_back : bool) #expand
{
	#assert (do_front || do_back);
	#assert (!by_pointer);

	#if reverse
	{
		#if do_back   start := gap_buffer_count (buffer) - 1;
		else          start := buffer.cursor - 1;
		#if do_front  end   := 0;
		else          end   := buffer.cursor;
	}
	else
	{
		#if do_front  start := 0;
		else          start := buffer.cursor;
		#if do_back   end   := gap_buffer_count (<<buffer) - 1;
		else          end   := buffer.cursor - 1;
	}

	for <=reverse `it_index : start..end
	{
		`it := (<<buffer)[`it_index];
		#insert (remove = #assert false "If you want to modify the contents of a gap buffer, move the cursor and do the operation.") body;	// @Compiler_Bug
	}
}
