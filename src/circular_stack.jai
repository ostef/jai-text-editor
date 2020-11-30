Circular_Stack :: struct (T : Type)
{
	data  : *T;
	count : s64;
	head  : int;
	tail  : int;
	full  : bool;

	allocator      : Allocator;
	allocator_data : *void;
}

make_circular_stack :: ($T : Type, capacity : int, allocator : Allocator = null, allocator_data := null) -> Circular_Stack (T) #must
{
	result : Circular_Stack (T);
	data := NewArray (xx capacity, T, allocator = allocator, allocator_data = null);
	result.data = data.data;
	result.count = data.count;
	result.allocator      = allocator;
	result.allocator_data = allocator_data;

	return result;
}

destroy_circular_stack :: (using stack : *$T/Circular_Stack)
{
	reset (stack);
	free (data, allocator = allocator, allocator_data = allocator_data);
	count = 0;
}

reset :: (using stack : *$T/Circular_Stack)
{
	head = 0;
	tail = 0;
	full = false;
}

push :: (using stack : *$T/Circular_Stack, elem : T.T)
{
	data[head] = elem;
	if full  tail = (tail + 1) % count;
	head = (head + 1) % count;
	full = head == tail;
}

peek :: (using stack : *$T/Circular_Stack) -> T.T
{
	assert (!is_empty (<<stack), "Cannot peek: stack is empty.");
	
	return data[head];
}

pop :: (using stack : *$T/Circular_Stack) -> T.T
{
	assert (!is_empty (<<stack), "Cannot pop: stack is empty.");
	head  = (head + count - 1) % count;
	elem := data[head];
	full  = false;

	return elem;
}

is_full :: inline (using stack : $T/Circular_Stack) -> bool
{
	return full;
}

is_empty :: inline (using stack : $T/Circular_Stack) -> bool
{
	return head == tail && !full;
}

get_count :: inline (using stack : $T/Circular_Stack) -> int
{
	if !full
	{
		if head >= tail  return head - tail;
		else             return count + head - tail;
	}

	return count;
}

get_count :: inline (using stack : *$T/Circular_Stack) -> int
{
	return get_count (<<stack);
}
