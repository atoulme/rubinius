require 'tmpdir'
require 'rakelib/rubinius'

require 'lib/ffi/generator_task.rb'

task :vm => 'vm/vm'

############################################################
# Files, Flags, & Constants

if ENV['LLVM_DEBUG']
  LLVM_STYLE = "Debug"
else
  LLVM_STYLE = "Release"
end

LLVM_ENABLE = ENV['LLVM_ENABLE']

if LLVM_ENABLE
  puts "[Compiling with LLVM]"
end


ENV.delete 'CDPATH' # confuses llvm_config
LLVM_CONFIG = "vm/external_libs/llvm/#{LLVM_STYLE}/bin/llvm-config"
tests       = FileList["vm/test/test_*.hpp"]

# vm/test/test_instructions.hpp may not have been generated yet
tests      << 'vm/test/test_instructions.hpp'
tests.uniq!

srcs        = FileList["vm/*.{cpp,c}"] + FileList["vm/builtin/*.{cpp,c}"]
srcs       += FileList["vm/subtend/*.{cpp,c,S}"]
srcs       += FileList["vm/parser/*.{cpp,c}"]
srcs       << 'vm/parser/grammar.cpp'

hdrs        = FileList["vm/*.{hpp,h}"] + FileList["vm/builtin/*.{hpp,h}"]
hdrs       += FileList["vm/subtend/*.{hpp,h}"]
hdrs       += FileList["vm/parser/*.{hpp,h}"]

objs        = srcs.map { |f| f.sub(/((c(pp)?)|S)$/, 'o') }

dep_file    = "vm/.depends.mf"
vm_objs     = %w[ vm/drivers/cli.o ]
vm_srcs     = %w[ vm/drivers/cli.cpp ]
EX_INC      = %w[ libtommath onig libffi/include
                  libbstring libcchash libmquark libmpa
                  libltdl libev llvm/include
                ].map { |f| "vm/external_libs/#{f}" }

INSN_GEN    = %w[ vm/gen/iseq_instruction_names.cpp
                  vm/gen/iseq_instruction_names.hpp
                  vm/gen/iseq_instruction_size.gen
                  vm/test/test_instructions.hpp ]
TYPE_GEN    = %w[ vm/gen/includes.hpp
                  vm/gen/typechecks.gen.cpp
                  vm/gen/primitives_declare.hpp
                  vm/gen/primitives_glue.gen.cpp ]

task :bogo_field_extract => TYPE_GEN

# Files are in order based on dependencies. For example,
# CompactLookupTable inherits from Tuple, so the header
# for compactlookuptable.hpp has to come after tuple.hpp
field_extract_headers = %w[
  vm/builtin/object.hpp
  vm/builtin/integer.hpp
  vm/builtin/executable.hpp
  vm/builtin/access_variable.hpp
  vm/builtin/fixnum.hpp
  vm/builtin/array.hpp
  vm/builtin/bignum.hpp
  vm/builtin/block_environment.hpp
  vm/builtin/bytearray.hpp
  vm/builtin/io.hpp
  vm/builtin/channel.hpp
  vm/builtin/module.hpp
  vm/builtin/class.hpp
  vm/builtin/compiledmethod.hpp
  vm/builtin/contexts.hpp
  vm/builtin/data.hpp
  vm/builtin/dir.hpp
  vm/builtin/exception.hpp
  vm/builtin/float.hpp
  vm/builtin/immediates.hpp
  vm/builtin/iseq.hpp
  vm/builtin/list.hpp
  vm/builtin/lookuptable.hpp
  vm/builtin/memorypointer.hpp
  vm/builtin/methodtable.hpp
  vm/builtin/nativefunction.hpp
  vm/builtin/regexp.hpp
  vm/builtin/selector.hpp
  vm/builtin/sendsite.hpp
  vm/builtin/staticscope.hpp
  vm/builtin/string.hpp
  vm/builtin/symbol.hpp
  vm/builtin/task.hpp
  vm/builtin/thread.hpp
  vm/builtin/tuple.hpp
  vm/builtin/compactlookuptable.hpp
  vm/builtin/time.hpp
  vm/builtin/methodvisibility.hpp
  vm/builtin/taskprobe.hpp
  vm/builtin/nativemethod.hpp
  vm/builtin/nativemethodcontext.hpp
  vm/builtin/system.hpp
]

BC          = "vm/instructions.bc"

EXTERNALS   = %W[ vm/external_libs/libmpa/libptr_array.a
                  vm/external_libs/libcchash/libcchash.a
                  vm/external_libs/libmquark/libmquark.a
                  vm/external_libs/libtommath/libtommath.a
                  vm/external_libs/libbstring/libbstring.a
                  vm/external_libs/onig/.libs/libonig.a
                  vm/external_libs/libffi/.libs/libffi.a
                  vm/external_libs/libltdl/.libs/libltdl.a
                  vm/external_libs/libev/.libs/libev.a ]

if LLVM_ENABLE
  LLVM_A = "vm/external_libs/llvm/#{LLVM_STYLE}/lib/libLLVMSystem.a"
  EXTERNALS << LLVM_A
else
  LLVM_A = ""
end

OPTIONS     = {
                LLVM_A => "--enable-targets=host-only"
              }

if LLVM_STYLE == "Release"
  OPTIONS[LLVM_A] << " --enable-optimized"
end

INCLUDES      = EX_INC + %w[/usr/local/include vm/test/cxxtest vm .]
INCLUDES.map! { |f| "-I#{f}" }

# Default build options
FLAGS         = %w[ -pipe -Wall -Wno-deprecated -ggdb3 -O2 -Werror ]
if RUBY_PLATFORM =~ /darwin/i && `sw_vers` =~ /10\.4/
  FLAGS.concat %w(-DHAVE_STRLCAT -DHAVE_STRLCPY)
end

if LLVM_ENABLE
  FLAGS << "-DENABLE_LLVM"
end

BUILD_PRETASKS = []

if ENV['DEV']
  BUILD_PRETASKS << "build:debug_flags"
end

CC          = ENV['CC'] || "gcc"

def compile_c(obj, src)
  flags = INCLUDES + FLAGS

  if LLVM_ENABLE
    unless defined? $llvm_c
      $llvm_c = `#{LLVM_CONFIG} --cflags`.split(/\s+/)
      $llvm_c.delete_if { |e| e.index("-O") == 0 }
    end
    flags.concat $llvm_c
  end

  # GROSS
  if src == "vm/test/runner.cpp"
    flags.delete_if { |f| /-O.*/.match(f) }
  end
  
  if src =~ /c$/
    # command line option "-Wno-deprecated" is valid for C++ but not for C
    flags.delete_if { |f| f == '-Wno-deprecated' }
  end


  flags = flags.join(" ")

  if $verbose
    sh "#{CC} #{flags} -c -o #{obj} #{src} 2>&1"
  else
    puts "CC #{src}"
    sh "#{CC} #{flags} -c -o #{obj} #{src} 2>&1", :verbose => false
  end
end

def ld t
  if LLVM_ENABLE
    $link_opts ||= `#{LLVM_CONFIG} --ldflags`.split(/\s+/).join(' ')
  else
    $link_opts ||= ""
  end

  $link_opts += ' -Wl,--export-dynamic' if RUBY_PLATFORM =~ /linux/i
  $link_opts += ' -rdynamic'            if RUBY_PLATFORM =~ /bsd/

  ld = ENV['LD'] || 'g++'
  o  = t.prerequisites.find_all { |f| f =~ /o$/ }.join(' ')
  l  = ex_libs.join(' ')

  if $verbose
    sh "#{ld} #{$link_opts} -o #{t.name} #{o} #{l}"
  else
    puts "LD #{t.name}"
    sh "#{ld} #{$link_opts} -o #{t.name} #{o} #{l}", :verbose => false
  end
end

def rubypp_task(target, prerequisite, *extra)
  file target => [prerequisite, 'vm/codegen/rubypp.rb'] + extra do
    path = File.join("vm/gen", File.basename(prerequisite))
    ruby 'vm/codegen/rubypp.rb', prerequisite, path
    yield path
  end
end

############################################################
# Other Tasks

# Build options.
namespace :build do

  # The top-level build task uses this, so undocumented.
  task :normal      => %w[ build:normal_flags build:build ]

  desc "Show methods that are not inlined in the optimized build"
  task :inline      => %w[ build:inline_flags build:build ]

  desc "Build debug image for GDB. No optimizations, more warnings."
  task :debug       => %w[ build:debug_flags build:build ]

  desc "Build to check for possible problems in the code. See build:help."
  task :strict      => %w[ build:strict_flags build:build ]

  desc "Build to enforce coding practices. See build:help for info."
  task :ridiculous  => %w[ build:ridiculous_flags build:build ]

  # Issue the actual build commands. NEVER USE DIRECTLY.
  task :build => BUILD_PRETASKS +
                 %w[ vm/vm
                     kernel:build
                     lib/rbconfig.rb
                     build:ffi:preprocessor
                     extensions
                   ]

  # Flag setup

  task :normal_flags do
  end

  task :inline_flags => :normal_flags do
    FLAGS.concat %w[ -Winline -Wuninitialized ]
  end

  # -Wuninitialized requires -O, so it is not here.
  task :debug_flags => "build:normal_flags" do
    FLAGS.delete "-O2"
    FLAGS.concat %w[ -O0 -fno-inline ]
  end

  task :strict_flags => "build:debug_flags" do
    FLAGS.concat %w[ -Wextra -W -pedantic
                     -Wshadow -Wfloat-equal -Wsign-conversion
                     -Wno-long-long -Wno-inline -Wno-unused-parameter
                   ]
  end

  task :ridiculous_flags => "build:strict_flags" do
    FLAGS.concat %w[ -Weffc++ ]
  end

  desc "Print more information about the build task options."
  task :help do
    puts <<-ENDHELP

  There are five ways to build the VM. Each of the last three
  special tasks is cumulative with the one(s) above it:


   Users
  -------

  build             Build normal, optimized image.


   Developers
  ------------

  build:inline      Use to check if any methods requested to be
                    inlined were not. The image is otherwise the
                    normal optimized one.

  build:debug       Use when you need to debug in GDB. Builds an
                    image with debugging symbols, optimizations
                    are disabled and more warnings emitted by the
                    compiler.

  build:strict      Use to check for and fix potential problems
                    in the codebase. Shows many more warnings.

  build:ridiculous  Use to enforce good practices. Adds warnings
                    for not abiding by "Efficient C++" guidelines
                    and treats all warnings as errors. It may be
                    necessary to disable some warning types for
                    this build.

  Notes:
    - If you do not want to use --trace but do want to see the exact
      shell commands issued for compilation, invoke Rake thus:

        `rake build:debug -- -v`

    ENDHELP
  end

  namespace :ffi do

    FFI_PREPROCESSABLES = %w[ lib/etc.rb
                              lib/fcntl.rb
                              lib/openssl/digest.rb
                              lib/syslog.rb
                              lib/zlib.rb
                            ]

    # Generate the .rb files from lib/*.rb.ffi
    task :preprocessor => FFI_PREPROCESSABLES

    FFI::Generator::Task.new FFI_PREPROCESSABLES

  end

end


# Compilation tasks

rule '.o' do |t|
  obj   = t.name
  src   = t.prerequisites.find { |f| f =~ /#{File.basename obj, '.o'}\.((c(pp)?)|S)$/}

  compile_c obj, src
end

def files targets, dependencies = nil, &block
  targets.each do |target|
    if dependencies then
      file target => dependencies, &block
    else
      file target, &block
    end
  end
end

directory "vm/gen"
file  "vm/type_info.o"    => "vm/gen/typechecks.gen.cpp"
file  "vm/primitives.hpp" => "vm/gen/primitives_declare.hpp"
files Dir["vm/builtin/*.hpp"], INSN_GEN
files vm_objs, vm_srcs

objs.zip(srcs).each do |obj, src|
  file obj => src
end

objs += ["vm/instructions.o"] # NOTE: BC isn't added due to llvm-g++ requirement

files EXTERNALS do |t|
  path = File.join(*split_all(t.name)[0..2])
  configure_path = File.join(path, 'configure')

  if File.exist? configure_path then
    sh "cd #{path}; ./configure #{OPTIONS[t.name]} && #{make}"
  else
    sh "cd #{path}; #{make}"
  end
end

file 'vm/primitives.o'                => 'vm/codegen/field_extract.rb'
file 'vm/primitives.o'                => TYPE_GEN
file 'vm/codegen/instructions_gen.rb' => 'kernel/delta/iseq.rb'
file 'vm/instructions.rb'             => 'vm/gen'
file 'vm/instructions.rb'             => 'vm/codegen/instructions_gen.rb'
file 'vm/test/test_instructions.hpp'  => 'vm/codegen/instructions_gen.rb'
file 'vm/codegen/field_extract.rb'    => 'vm/gen'

files INSN_GEN, %w[vm/instructions.rb] do |t|
  ruby 'vm/instructions.rb', :verbose => $verbose
end

task :run_field_extract do
  field_extract field_extract_headers
end

files TYPE_GEN, field_extract_headers + %w[vm/codegen/field_extract.rb] + [:run_field_extract] do
end

file 'vm/drivers/llvm.o' => 'vm/drivers/llvm.cpp'

file 'vm/vm' => EXTERNALS + objs + vm_objs do |t|
  ld t
end

file 'vm/llvm-compile' => EXTERNALS + objs + ['vm/drivers/llvm.o'] do |t|
  ld t
end

file 'vm/gen/primitives_glue.gen.cpp' => hdrs

file 'vm/test/runner.cpp' => tests + objs do
  tests = tests.sort
  puts "GEN vm/test/runner.cpp" unless $verbose
  tests << { :verbose => $verbose }
  sh("vm/test/cxxtest/cxxtestgen.pl", "--error-printer", "--have-eh",
     "--abort-on-fail", "-include=string.h", "-include=stdlib.h", "-o", "vm/test/runner.cpp", *tests)
end

file 'vm/parser/grammar.cpp' => 'vm/parser/grammar.y' do
  src = 'vm/parser/grammar.y'
  bison = "bison -o vm/parser/grammar.cpp #{src}"
  if $verbose
    sh bison
  else
    puts "BISON #{src}"
    sh bison, :verbose => false
  end
end

file 'vm/test/runner.o' => 'vm/test/runner.cpp' # no rule .o => .cpp

file 'vm/test/runner' => EXTERNALS + objs + %w[vm/test/runner.o] do |t|
  ld t
end

# A simple JIT tester driver

file 'vm/drivers/compile.o' => 'vm/drivers/compile.cpp'

file 'vm/compile' => EXTERNALS + objs + %w[vm/drivers/compile.o] do |t|
  ld t
end

rubypp_task 'vm/instructions.o', 'vm/llvm/instructions.cpp', 'vm/instructions.rb', *hdrs do |path|
  compile_c 'vm/instructions.o', path
end

rubypp_task 'vm/instructions.bc', 'vm/llvm/instructions.cpp', *hdrs do |path|
  sh "llvm-g++ -emit-llvm -O2 -I. -Ivm -Ivm/external_libs/libtommath -Ivm/external_libs/libffi/include -c -o vm/instructions.bc #{path}"
end

namespace :vm do
  desc 'Run all VM tests.  Uses its argument as a filter of tests to run.'
  task :test, :filter do |task, args|
    ENV['SUITE'] = args[:filter] if args[:filter]
    ENV['VERBOSE'] = '1' if $verbose
    sh 'vm/test/runner', :verbose => $verbose
  end

  task :test => %w[ build:debug_flags vm/test/runner ]

  task :coverage do
    Dir.mkdir "vm/test/coverage" unless File.directory? "vm/test/coverage"
    if LLVM_ENABLE
      unless defined? $llvm_c
        $llvm_c = `#{LLVM_CONFIG} --cflags`.split(/\s+/)
        $llvm_c.delete_if { |e| e.index("-O") == 0 }
      end
    end

    if LLVM_ENABLE
      $link_opts ||= `#{LLVM_CONFIG} --ldflags`.split(/\s+/).join(' ')
    else
      $link_opts ||= ""
    end

    flags = (INCLUDES + FLAGS + $llvm_c).join(' ')

    puts "CC/LD vm/test/coverage/runner"
    begin
      path = "vm/gen/instructions.cpp"
      ruby 'vm/codegen/rubypp.rb', "vm/llvm/instructions.cpp", path
      sh "g++ -fprofile-arcs -ftest-coverage #{flags} -o vm/test/coverage/runner vm/test/runner.cpp vm/*.cpp vm/builtin/*.cpp #{path} #{$link_opts} #{(ex_libs + EXTERNALS).join(' ')}"

      puts "RUN vm/test/coverage/runner"
      sh "vm/test/coverage/runner"
      if $verbose
        sh "vm/test/lcov/bin/lcov --directory . --capture --output-file vm/test/coverage/app.info"
      else
        sh "vm/test/lcov/bin/lcov --directory . --capture --output-file vm/test/coverage/app.info > /dev/null 2>&1"
      end

      puts "GEN vm/test/coverage/index.html"
      if $verbose
        sh "cd vm/test/coverage; ../lcov/bin/genhtml app.info"
      else
        sh "cd vm/test/coverage; ../lcov/bin/genhtml app.info > /dev/null 2>&1"
      end
    ensure
      sh "rm -f *.gcno *.gcda"
    end
  end

  # TODO: for ryan: fix up dependencies between rubypp and the source files now that they're persistent
  # TODO: for ryan: dependencies on vm/test/test_instructions.hpp causes rebuild of vm/*.cpp files. lame

  desc "Clean up vm build files"
  task :clean do
    files = [
      objs, vm_objs, dep_file, TYPE_GEN, INSN_GEN,
      'vm/gen',
      'vm/test/runner',
      'vm/test/runner.cpp',
      'vm/test/test_instructions.cpp',
      'vm/vm'
    ].flatten

    files.each do |filename|
      rm_rf filename, :verbose => $verbose
    end
  end

  desc "Clean up, including all external libs"
  task :distclean => :clean do
    EXTERNALS.each do |lib|
      path = File.join(*lib.split(File::SEPARATOR)[0..2])
      system "cd #{path}; #{make} clean"
    end
  end

  desc "Show which primitives are missing"
  task :missing_primitives do
    kernel_files = FileList['kernel/**/*.rb'].join " "
    kernel_primitives = `grep 'Ruby.primitive' #{kernel_files} | awk '{ print $3 }'`
    kernel_primitives = kernel_primitives.gsub(':', '').split("\n").sort.uniq

    cpp_primitives = `grep 'Ruby.primitive' vm/builtin/*.hpp | awk '{ print $4 }'`
    cpp_primitives = cpp_primitives.gsub(':', '').split("\n").sort.uniq

    missing = kernel_primitives - cpp_primitives

    puts missing.join("\n")
  end
end

############################################################$
# Importers & Methods:

require 'rake/loaders/makefile'

generated = (TYPE_GEN + INSN_GEN).select { |f| f =~ /pp$/ }

file dep_file => srcs + hdrs + vm_srcs + generated do |t|
  includes = INCLUDES.join ' '

  flags = FLAGS.join ' '
  flags << " -D__STDC_LIMIT_MACROS"

  cmd = "makedepend -f- #{includes} -- #{flags} -- #{t.prerequisites.join(' ')}"
  cmd << ' 2>/dev/null' unless $verbose
  warn "makedepend ..."

  dep = `#{cmd}`
  if $?.exitstatus != 0
    fail "error executing `makedepend`; is it in your $PATH\?"
  end
  dep.gsub!(%r% /usr/include\S+%, '') # speeds up rake a lot
  dep.gsub!(%r%^\S+:[^ ]%, '')

  File.open t.name, 'w' do |f|
    f.puts dep
  end
end

import dep_file

def ex_libs # needs to be method to delay running of llvm_config
  unless defined? $ex_libs then
    $ex_libs = EXTERNALS.reverse
    $ex_libs << "-ldl" unless RUBY_PLATFORM =~ /bsd/
    $ex_libs << "-lcrypt -L/usr/local/lib -lexecinfo" if RUBY_PLATFORM =~ /bsd/
    $ex_libs << "-lrt -lcrypt" if RUBY_PLATFORM =~ /linux/

    if LLVM_ENABLE
      llvm_libfiles = `#{LLVM_CONFIG} --libfiles all`.split(/\s+/)
      llvm_libfiles = llvm_libfiles.select { |f| File.file? f }
    else
      llvm_libfiles = []
    end

    pwd = File.join Dir.pwd, '' # add /
    llvm_libfiles = llvm_libfiles.map { |f| f.sub pwd, '' }
    $ex_libs += llvm_libfiles
  end
  $ex_libs
end

def field_extract(headers)
  headers += [{ :verbose => $verbose}]

  ruby('vm/codegen/field_extract.rb', *headers)
end
