// We provide a certain number of language token such as comment, identifier, keywords,
// but a language can define its own that will be lookup up in the theme, and if not
// found it will default to a built-in one.

Jai_Token_Kind :: enum
{
	UNKNOWN; //@Token(invalid)
	COMMENT; //@Token(comment)
	
	IDENTIFIER; //@Token(identifier)
	CONTROL_KEYWORD; //@Token(keyword,keyword_control)
	STORAGE_TYPE_KEYWORD; //@Token(keyword,keyword_storage_type)
	TYPE_KEYWORD; //@Token(keyword,keyword_type)
	FUNCTION_KEYWORD; //@Token(keyword,keyword_function)
	OTHER_KEYWORD; //@Token(keyword)

	STRING_LITERAL; //@Token(string)
	NUMBER_LITERAL; //@Token(number)
	INVALID_NUMBER_LITERAL; //@Token(invalid,invalid_number_literal)

	POLYMORPHIC_ARGUMENT; //@Token(tag,polymorphic)
	COMPILER_DIRECTIVE; //@Token(tag,compiler_directive)
	INVALID_COMPILER_DIRECTIVE; //@Token(invalid,invalid_compiler_directive)
	NOTE; //@Token(tag)
	
	SYMBOL; //@Token(symbol)
	EOI;
}

Jai_Token :: Token (Jai_Token_Kind);

JAI_CONTROL_KEYWORDS :: string.[ "if", "ifx", "then", "else", "case", "for", "while", "break", "continue", "return", "using", "inline" ];
JAI_STORAGE_TYPE_KEYWORDS :: string.[ "struct", "union", "enum", "enum_flags" ];
JAI_TYPE_KEYWORDS :: string.[ "void", "u8", "u16", "u32", "u64", "s8", "s16", "s32", "s64", "int", "float32", "float64", "f32", "f64", "float", "bool", "string" ];
JAI_FUNCTION_KEYWORDS :: string.[ "cast", "xx", "type_of", "type_info", "size_of", "align_of", "initializer_of" ];
JAI_OTHER_KEYWORDS :: string.[ "push_context", "context", "null", "true", "false", "it", "it_index", "no_check", "truncate", "no_dll", "stallable" ];
JAI_COMPILER_DIRECTIVES :: string.[
	"import", "load", "foreign", "foreign_library", "foreign_system_library", "must", "no_abc", "insert", "insert_internal",
	"run", "char", "place", "through", "expand", "if", "scope_file", "scope_module", "scope_export", "assert", "bake", "bake_arguments", "bake_constants",
	"complete", "string", "no_reset", "dump", "code", "caller_location", "c_call", "c_callback", "module_parameters", "elsewhere", "placeholder", "instrinsic",
	"compiler", "symmetric", "modify", "cpp_return_type_is_non_pod", "cpp_method", "add_context", "dynamic_specialize", "specified", "filepath", "file", "line",
	"poke_name", "program_export", "procedure_of_call", "location", "type_info_none", "type_info_procedures_are_void_pointers", "type_info_no_size_complaint",
	"no_alias", "type", "deprecated", "align" ];

jai_read_next_token :: (using lexer : *Lexer) -> Jai_Token #must
{
	skip_spaces (lexer);
	result : Jai_Token;
	result.kind = .UNKNOWN;
	set_token_start (lexer, *result);
	set_token_end (lexer, *result);

	if curr == end
	{
		result.kind = .EOI;
	}
	else if advance_if_matches (lexer, "//")
	{
		result.kind = .COMMENT;
		advance_to_newline (lexer);
		set_token_end (lexer, *result);
	}
	else if advance_if_matches (lexer, "/*")
	{
		result.kind = .COMMENT;
		level := 1;
		while curr < end && level != 0
		{
			if advance_if_matches (lexer, "/*")
				level += 1;
			else if advance_if_matches (lexer, "*/")
				level -= 1;
			else
				advance (lexer);
		}
		set_token_end (lexer, *result);
	}
	else if is_alpha (<<curr) || <<curr == #char "_"
	{
		while curr < end && is_alpha_num (<<curr)
			advance (lexer);

		set_token_end (lexer, *result);
		control_kw := find_first_occurence (JAI_CONTROL_KEYWORDS, result.str);
		if control_kw != -1 { result.kind = .CONTROL_KEYWORD; return result; }

		storage_type_kw := find_first_occurence (JAI_STORAGE_TYPE_KEYWORDS, result.str);
		if storage_type_kw != -1 { result.kind = .STORAGE_TYPE_KEYWORD; return result; }
		
		type_kw := find_first_occurence (JAI_TYPE_KEYWORDS, result.str);
		if type_kw != -1 { result.kind = .TYPE_KEYWORD; return result; }
		
		function_kw := find_first_occurence (JAI_FUNCTION_KEYWORDS, result.str);
		if function_kw != -1 { result.kind = .FUNCTION_KEYWORD; return result; }

		other_kw := find_first_occurence (JAI_OTHER_KEYWORDS, result.str);
		if other_kw != -1 { result.kind = .OTHER_KEYWORD; return result; }
	
		result.kind = .IDENTIFIER;
	}
	else if is_digit (<<curr)
	{
		is_float_hex := advance_if_matches (lexer, "0h");
		is_int_hex   := false;
		if !is_float_hex then is_int_hex = advance_if_matches (lexer, "0x");
		is_int_bin   := false;
		if !is_float_hex && !is_int_hex then is_int_bin = advance_if_matches (lexer, "0b");

		valid := true;
		found_decimal     := false;
		found_exponent    := false;
		last_was_decimal  := false;
		last_was_exponent := false;
		digit_count          := 0;
		whole_digit_count    := 0;
		decimal_digit_count  := 0;
		exponent_digit_count := 0;
		while curr < end
		{
			if matches (lexer, "..")
			{
				break;
			}
			else if <<curr == #char "."
			{
				if found_exponent || found_decimal || is_float_hex || is_int_hex || is_int_bin then valid = false;
				found_decimal    = true;
				last_was_decimal = true;
			}
			else if <<curr == #char "e" && !is_float_hex && !is_int_hex
			{
				if digit_count == 0 || found_exponent || is_int_bin then valid = false;
				found_exponent    = true;
				last_was_exponent = true;
			}
			else if is_alpha_num (<<curr)
			{
				if (is_float_hex || is_int_hex) && !is_hex_digit (<<curr) then valid = false;
				if is_int_bin && !is_bin_digit (<<curr) then valid = false;
				if <<curr == #char "_" && last_was_exponent then valid = false;

				digit_count += 1;
				if found_exponent then exponent_digit_count += 1;
				else if found_decimal then decimal_digit_count += 1;
				else whole_digit_count += 1;
				last_was_decimal  = false;
				last_was_exponent = false;
			}
			else
			{
				break;
			}

			advance (lexer);
		}

		if digit_count == 0 ||
			found_decimal && decimal_digit_count == 0 ||
			found_exponent && exponent_digit_count == 0
		{
			valid = false;
		}

		result.kind = ifx valid then Jai_Token_Kind.NUMBER_LITERAL else Jai_Token_Kind.INVALID_NUMBER_LITERAL;
		set_token_end (lexer, *result);
	}
	else if <<curr == #char "\""
	{
		advance (lexer);
		while curr < end && <<curr != #char "\""
		{
			if <<curr == #char "\\" then advance (lexer);
			advance (lexer);
		}
		advance (lexer);

		set_token_end (lexer, *result);
		result.kind = .STRING_LITERAL;
	}
	else if <<curr == #char "#"
	{
		advance (lexer);
		skip_spaces (lexer);	// #                   import is a valid compiler directive, same for newlines between the '#' and the keyword
		while curr < end && is_alpha_num (<<curr)
			advance (lexer);
		
		set_token_end (lexer, *result);
		compiler_directive := find_first_occurence (JAI_COMPILER_DIRECTIVES, skip_spaces (advance (result.str)));
		if compiler_directive == -1 then result.kind = .INVALID_COMPILER_DIRECTIVE;
		else result.kind = .COMPILER_DIRECTIVE;
	}
	else if <<curr == #char "$"
	{
		advance (lexer);
		while curr < end && !is_space (<<curr)
			advance (lexer);

		set_token_end (lexer, *result);
		result.kind = .POLYMORPHIC_ARGUMENT;
	}
	else if <<curr == #char "@"
	{
		advance (lexer);
		while curr < end && !is_space (<<curr)
			advance (lexer);

		set_token_end (lexer, *result);
		result.kind = .NOTE;
	}
	else
	{
		advance (lexer);
		set_token_end (lexer, *result);
		result.kind = .SYMBOL;
	}

	return result;
}

set_token_start :: inline (using lexer : *Lexer, token : *Jai_Token)
{
	token.start = curr;
	token.l0    = l0;
	token.c0    = c0;
}

set_token_end :: inline (using lexer : *Lexer, token : *Jai_Token)
{
	token.end = curr;
	token.l1  = l0;
	token.c1  = c0;
	token.str.data  = token.start;
	token.str.count = token.end - token.start;
}
