Framebuffer :: struct
{
	fbo : GLuint;
	texture : GLuint;
	width, height : u32;
}

create_framebuffer :: (width : u32, height : u32) -> Framebuffer #must
{
	result : Framebuffer;
	result.width  = width;
	result.height = height;
	// Generate texture
	glGenTextures (1, *result.texture);
	glBindTexture (GL_TEXTURE_2D, result.texture);
	defer glBindTexture (GL_TEXTURE_2D, 0);
	glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
	// Generate framebuffer
	glGenFramebuffers (1, *result.fbo);
	glBindFramebuffer (GL_FRAMEBUFFER, result.fbo);
	defer glBindFramebuffer (GL_FRAMEBUFFER, 0);
	glFramebufferTexture2D (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, result.texture, 0);
	assert (glCheckFramebufferStatus (GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "Could not initialize framebuffer.");

	return result;
}

destroy_framebuffer :: (using framebuffer : *Framebuffer)
{
	glDeleteFramebuffers (1, *fbo);
	glDeleteTextures (1, *texture);
	fbo = 0;
	texture = 0;
	width = 0;
	height = 0;
}

resize_framebuffer :: (using framebuffer : *Framebuffer, new_width : u32, new_height : u32)
{
	if width == new_width && height == new_height then return;

	glBindFramebuffer (GL_FRAMEBUFFER, fbo);
	defer glBindFramebuffer (GL_FRAMEBUFFER, 0);
	glBindTexture (GL_TEXTURE_2D, texture);
	defer glBindTexture (GL_TEXTURE_2D, 0);
	glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, new_width, new_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);

	width = new_width;
	height = new_height;
}
