# Tasks for building C extensions used mainly by Rubinius, but also by MRI in
# the case of the Melbourne parser extension. The task names are defined to
# permit running the tasks directly, eg
#
#   rake compile:melbourne_rbx
#
# See rakelib/ext_helper.rb for the helper methods and Rake rules.

desc "Build extensions from lib/ext"
task :extensions

namespace :extensions do
  desc "Clean all lib/ext files"
  task :clean do
    rm_f FileList["lib/ext/**/*.{o,#{$dlext}}"], :verbose => $verbose
  end
end

def compile_ext(name, opts={})
  names = name.split ":"
  name = names.last
  ext_dir = File.join "lib/ext", names

  if t = opts[:task]
    ext_task_name = "build:#{t}"
    names << t
  else
    ext_task_name = "build"
  end

  task_name = names.join "_"

  namespace :extensions do
    desc "Build #{name.capitalize} extension #{opts[:doc]}"
    task task_name do
      ext_helper = File.expand_path "../ext_helper.rb", __FILE__
      Dir.chdir ext_dir do
        if File.exists? "Rakefile"
          ruby "-S rake #{'-t' if $verbose} -r #{ext_helper} #{ext_task_name}"
        else
          ruby "extconf.rb"
          if File.exists?("Makefile")
            sh "make"
          else
            warn "Unable to build #{name}"
          end
        end
      end
    end
  end

  Rake::Task[:extensions].prerequisites << "extensions:#{task_name}"
end

compile_ext "bigdecimal"
compile_ext "readline"
compile_ext "digest"
compile_ext "digest:md5"
compile_ext "digest:rmd160"
compile_ext "digest:sha1"
compile_ext "digest:sha2"
compile_ext "digest:bubblebabble"
compile_ext "syck"
compile_ext "openssl"
compile_ext "melbourne", :task => "rbx", :doc => "for Rubinius"
compile_ext "melbourne", :task => "mri", :doc => "for MRI"
