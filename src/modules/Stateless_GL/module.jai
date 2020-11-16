#import "GL";

GL_CLIP_PLANE0 :: 0x3000;
GL_CLIP_PLANE1 :: 0x3001;
GL_CLIP_PLANE2 :: 0x3002;
GL_CLIP_PLANE3 :: 0x3003;
GL_CLIP_PLANE4 :: 0x3004;
GL_CLIP_PLANE5 :: 0x3005;

GL_State :: struct
{
	viewport_x, viewport_y : GLint;
	viewport_w, viewport_h : GLsizei;
	depth_near, depth_far : GLdouble;
	clear_r, clear_g, clear_b, clear_a : GLfloat;
	clear_depth : float;
	clear_stencil : GLint;
	cull_face : GLenum = GL_BACK;
	front_face : GLenum = GL_CCW;
	// glEnable/glDisable
	// @Todo (stefan): More glEnable/glDisable booleans
	enable_blend : bool;
	enable_clip_plane : [6]bool;
	enable_cull_face : bool;
	enable_depth_test : bool;
	enable_multisample : bool;
	enable_scissor_test : bool;
	enable_stencil_test : bool;

	// @Todo (stefan): glHint

	blend_src_rgb : GLenum = GL_ONE;
	blend_dest_rgb : GLenum = GL_ZERO;
	blend_src_alpha : GLenum = GL_ONE;
	blend_dest_alpha : GLenum = GL_ZERO;
	blend_equation_rgb : GLenum = GL_FUNC_ADD;
	blend_equation_alpha : GLenum = GL_FUNC_ADD;
	depth_func : GLenum = GL_LESS;
	stencil_func : GLenum = GL_ALWAYS;
	stencil_ref : GLint;
	stencil_mask : GLuint = 0xffffffff;
	
	spo, fbo, vao, vbo, ibo : GLuint;
	tex : [32]GLuint;
}

GL_STATE_DEFAULT :: GL_State.{};

make_gl_state :: (
	viewport_x : GLint = 0, viewport_y : GLint = 0, viewport_w : GLsizei = 0, viewport_h : GLsizei = 0, 
	depth_near : GLdouble = 0, depth_far : GLdouble = 0,
	clear_r : GLfloat = 0, clear_g : GLfloat = 0, clear_b : GLfloat = 0, clear_a : GLfloat = 0,
	clear_depth : GLfloat = 0,
	clear_stencil : GLint = 0,
	cull_face : GLenum = GL_BACK, front_face : GLenum = GL_CCW,
	enable_blend := false,
	enable_clip_plane := bool.[ false, false, false, false, false, false ],
	enable_cull_face := false,
	enable_depth_test := false,
	enable_multisample := false,
	enable_scissor_test := false,
	enable_stencil_test := false,
	blend_src_rgb : GLenum = GL_ONE, blend_dest_rgb : GLenum = GL_ZERO,
	blend_src_alpha : GLenum = GL_ONE, blend_dest_alpha : GLenum = GL_ZERO,
	blend_equation_rgb : GLenum = GL_FUNC_ADD, blend_equation_alpha : GLenum = GL_FUNC_ADD,
	depth_func : GLenum = GL_LESS,
	stencil_func : GLenum = GL_ALWAYS,
	stencil_ref : GLint = 0,
	stencil_mask : GLuint = 0xffffffff,
	spo : GLuint = 0, fbo : GLuint = 0, vao : GLuint = 0, vbo : GLuint = 0, ibo : GLuint = 0,
	tex := GLuint.[ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ]) -> GL_State
{
	state : GL_State;
	state.viewport_x = viewport_x;
	state.viewport_y = viewport_y;
	state.viewport_w = viewport_w;
	state.viewport_h = viewport_h;
	state.depth_near = depth_near;
	state.depth_far = depth_far;
	state.clear_r = clear_r;
	state.clear_g = clear_g;
	state.clear_b = clear_b;
	state.clear_a = clear_a;
	state.clear_depth = clear_depth;
	state.clear_stencil = clear_stencil;
	state.cull_face = cull_face;
	state.front_face = front_face;
	state.enable_blend = enable_blend;
	state.enable_clip_plane = enable_clip_plane;
	state.enable_cull_face = enable_cull_face;
	state.enable_depth_test = enable_depth_test;
	state.enable_multisample = enable_multisample;
	state.enable_scissor_test = enable_scissor_test;
	state.enable_stencil_test = enable_stencil_test;
	state.blend_src_rgb = blend_src_rgb;
	state.blend_dest_rgb = blend_dest_rgb;
	state.blend_src_alpha = blend_src_alpha;
	state.blend_dest_alpha = blend_dest_alpha;
	state.blend_equation_rgb = blend_equation_rgb;
	state.blend_equation_alpha = blend_equation_alpha;
	state.depth_func = depth_func;
	state.stencil_func = stencil_func;
	state.stencil_ref = stencil_ref;
	state.stencil_mask = stencil_mask;
	state.spo = spo;
	state.fbo = fbo;
	state.vao = vao;
	state.vbo = vbo;
	state.ibo = ibo;
	state.tex = tex;

	return state;
}

set_gl_state :: (using state : GL_State)
{
	glViewport (viewport_x, viewport_y, viewport_w, viewport_h);
	glDepthRange (depth_near, depth_far);
	glClearColor (clear_r, clear_g, clear_b, clear_a);
	glClearDepth (clear_depth);
	glClearStencil (clear_stencil);
	glCullFace (cull_face);
	glFrontFace (front_face);

	gl_set (GL_BLEND, enable_blend);
	for i : 0..enable_clip_plane.count-1  gl_set (GL_CLIP_PLANE0 + cast (u32) i, enable_clip_plane[i]);
	gl_set (GL_CULL_FACE, enable_cull_face);
	gl_set (GL_DEPTH_TEST, enable_depth_test);
	gl_set (GL_MULTISAMPLE, enable_multisample);
	gl_set (GL_SCISSOR_TEST, enable_scissor_test);
	gl_set (GL_STENCIL_TEST, enable_stencil_test);

	glBlendFuncSeparate (blend_src_rgb, blend_dest_rgb, blend_src_alpha, blend_dest_alpha);
	glBlendEquationSeparate (blend_equation_rgb, blend_equation_alpha);
	glDepthFunc (depth_func);
	glStencilFunc (stencil_func, stencil_ref, stencil_mask);

	glUseProgram (spo);
	glBindFramebuffer (GL_FRAMEBUFFER, fbo);
	glBindVertexArray (vao);
	glBindBuffer (GL_ARRAY_BUFFER, vbo);
	glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, ibo);
	
	for i : 0..tex.count-1
	{
		glActiveTexture (GL_TEXTURE0 + cast (u32) i);
		glBindTexture (GL_TEXTURE_2D, tex[i]);
	}

	glActiveTexture (GL_TEXTURE0);
}

get_gl_state :: () -> GL_State
{
	using state : GL_State;

	glGetIntegerv (GL_VIEWPORT, *viewport_x);
	glGetDoublev (GL_DEPTH_RANGE, *depth_near);
	glGetFloatv (GL_COLOR_CLEAR_VALUE, *clear_r);
	glGetFloatv (GL_DEPTH_CLEAR_VALUE, *clear_depth);
	glGetIntegerv (GL_STENCIL_CLEAR_VALUE, *clear_stencil);
	glGetIntegerv (GL_CULL_FACE_MODE, xx *cull_face);
	// front_face ???

	enable_blend = glIsEnabled (GL_BLEND);
	for i : 0..enable_clip_plane.count-1  enable_clip_plane[i] = glIsEnabled (GL_CLIP_PLANE0 + cast (u32) i);
	enable_cull_face = glIsEnabled (GL_CULL_FACE);
	enable_depth_test = glIsEnabled (GL_DEPTH_TEST);
	enable_multisample = glIsEnabled (GL_MULTISAMPLE);
	enable_scissor_test = glIsEnabled (GL_SCISSOR_TEST);
	enable_stencil_test = glIsEnabled (GL_STENCIL_TEST);

	glGetIntegerv (GL_BLEND_SRC_RGB, xx *blend_src_rgb);
	glGetIntegerv (GL_BLEND_DST_RGB, xx *blend_dest_rgb);
	glGetIntegerv (GL_BLEND_SRC_ALPHA, xx *blend_src_alpha);
	glGetIntegerv (GL_BLEND_DST_ALPHA, xx *blend_dest_alpha);
	glGetIntegerv (GL_BLEND_EQUATION_RGB, xx *blend_equation_rgb);
	glGetIntegerv (GL_BLEND_EQUATION_ALPHA, xx *blend_equation_alpha);
	glGetIntegerv (GL_DEPTH_FUNC, xx *depth_func);
	glGetIntegerv (GL_STENCIL_FUNC, xx *stencil_func);
	glGetIntegerv (GL_STENCIL_REF, *stencil_ref);
	glGetIntegerv (GL_STENCIL_VALUE_MASK, xx *stencil_mask);

	glGetIntegerv (GL_CURRENT_PROGRAM, xx *spo);
	glGetIntegerv (GL_VERTEX_ARRAY_BINDING, xx *vao);
	glGetIntegerv (GL_ARRAY_BUFFER_BINDING, xx *vbo);
	glGetIntegerv (GL_ELEMENT_ARRAY_BUFFER_BINDING, xx *ibo);

	for i : 0..tex.count-1
	{
		glActiveTexture (GL_TEXTURE0 + cast (u32) i);
		glGetIntegerv (GL_TEXTURE_BINDING_2D, xx *tex[i]);
	}

	glActiveTexture (GL_TEXTURE0);

	return state;
}

#scope_file

gl_set :: inline (mode : GLenum, val : bool)
{
	if val  glEnable (mode);
	else    glDisable (mode);
}
