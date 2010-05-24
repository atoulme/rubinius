#include "ruby.h"
#include <stdio.h>
#include <string.h>

VALUE exception_spec_rb_exc_new(VALUE self, VALUE str) {
  char *cstr = StringValuePtr(str);
  return rb_exc_new(rb_eException, cstr, strlen(cstr));
}

VALUE exception_spec_rb_exc_new2(VALUE self, VALUE str) {
  char *cstr = StringValuePtr(str);
  return rb_exc_new2(rb_eException, cstr);
}

VALUE exception_spec_rb_exc_new3(VALUE self, VALUE str) {
  return rb_exc_new3(rb_eException, str);
}

VALUE exception_spec_rb_exc_raise(VALUE self, VALUE exc) {
  rb_exc_raise(exc);
  return Qnil;
}

#if defined(RUBINIUS) || (RUBY_VERSION_MAJOR == 1 && RUBY_VERSION_MINOR >= 9)
VALUE exception_spec_rb_set_errinfo(VALUE self, VALUE exc) {
  rb_set_errinfo(exc);
  return Qnil;
}
#endif

void Init_exception_spec() {
  VALUE cls;
  cls = rb_define_class("CApiExceptionSpecs", rb_cObject);
  rb_define_method(cls, "rb_exc_new", exception_spec_rb_exc_new, 1);
  rb_define_method(cls, "rb_exc_new2", exception_spec_rb_exc_new2, 1);
  rb_define_method(cls, "rb_exc_new3", exception_spec_rb_exc_new3, 1);
  rb_define_method(cls, "rb_exc_raise", exception_spec_rb_exc_raise, 1);
#if defined(RUBINIUS) || (RUBY_VERSION_MAJOR == 1 && RUBY_VERSION_MINOR >= 9)
  rb_define_method(cls, "rb_set_errinfo", exception_spec_rb_set_errinfo, 1);
#endif
}
