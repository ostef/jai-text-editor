#import "Hash";

Profiling_Entry :: struct
{
	procedure_name : string;
	block_name     := "";
	filename       : string;
	line           : s64;
	hash : u32;
	
	count : s64;
	min_time   := F64_POSITIVE_INFINITY;
	max_time   := F64_NEGATIVE_INFINITY;
	total_time : f64;

	current_start_time : f64;
}

#scope_file

profiling_data : [..]Profiling_Entry;
enable_profiling := false;

#scope_export

init_profiler :: ()
{
#if ENABLE_PROFILING
{
	init_array (*profiling_data, 1000, heap_allocator);
}
}

write_profiling_data_to_file :: (filename : string) -> bool
{
#if ENABLE_PROFILING
{
	builder := make_string_builder (5000, temp_allocator);
	for profiling_data
	{
		print_to_builder (*builder, "'%', '%' (line %), ", it.filename, it.procedure_name, it.line);
		if it.block_name then print_to_builder (*builder, "'%', ", it.block_name);
		print_line_to_builder (*builder, "profiled % times,\n\tmin: % ms, max: % ms, avg: % ms", it.count, it.min_time * 1000.0, it.max_time * 1000.0, it.total_time * 1000.0 / xx it.count);
	}
	
	written, ok := write_to_file (filename, to_string (builder), create = true);
	
	return ok;
}
else
{
	return true;
}
}

#scope_file

find_or_add_profiling_entry :: (block_name : string) -> s64 #must
{
	assert (context.stack_trace != null, "Cannot start profiling block because stack trace information is not present.");
	// @Note (stefan): In how_to/700_stack_trace.jai: "The strings are stored in the executable, so you don't need to allocate copies of them."
	procedure_name := context.stack_trace.info.name;
	filename       := context.stack_trace.info.location.fully_pathed_filename;
	line           := context.stack_trace.info.location.line_number;
	hash           : u32;
	if block_name then hash = default_hash (join (temp_allocator, procedure_name, block_name, filename)) ^ default_hash (line);
	else               hash = default_hash (join (temp_allocator, procedure_name, filename)) ^ default_hash (line);
	
	for profiling_data
		if it.hash == hash then return it_index;
	
	profiling := push_to_array (*profiling_data, initialize = true);
	profiling.procedure_name = procedure_name;
	profiling.block_name     = block_name;
	profiling.filename       = filename;
	profiling.line           = line;
	profiling.hash           = hash;
	
	return profiling_data.count - 1;
}

#scope_export

profile :: (block_name := "") #expand
{
#if ENABLE_PROFILING
{
	procedure_info := context.stack_trace.info;
	`__profiling_entry_index := find_or_add_profiling_entry (block_name);
	profiling_data[__profiling_entry_index].count += 1;
	profiling_data[__profiling_entry_index].current_start_time = get_time ();
	`defer
	{
		profiling_entry := *profiling_data[__profiling_entry_index];
		elapsed := get_time () - profiling_entry.current_start_time;
		profiling_entry.total_time += elapsed;
		if elapsed < profiling_entry.min_time then profiling_entry.min_time = elapsed;
		if elapsed > profiling_entry.max_time then profiling_entry.max_time = elapsed;
	}
}
}
