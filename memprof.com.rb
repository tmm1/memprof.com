#!/Users/test/.rvm/rubies/ruby-1.8.7-p249/bin/ruby

require 'rubygems'
require 'mongo'
require 'pp'

module Memprof
  class Dump
    def initialize(collection_name)
      @@connection ||= Mongo::Connection.new

      @db = @@connection.db('memprof_datasets').collection(collection_name.to_s)
      @db.create_index(:type)
      @db.create_index(:super)
      @db.create_index(:file)
      @db.create_index(:class)

      @refs = @@connection.db('memprof_datasets').collection("#{collection_name}_refs")
      @refs.create_index(:refs)

      @root_object = @db.find_one(:type => 'class', :name => 'Object')
    end
    attr_reader :db, :refs, :root_object

    def subclasses_of(klass = nil, type = 'class')
      klass ||= root_object
      subclasses = []
      process_children = proc{ |obj_id| 
        children = @db.find(:super => obj_id)
        children.each do |child|
          if child['type'] == type
            subclasses << child
          else
            process_children.call(child['_id'])
          end
        end
      }
      process_children.call(klass['_id'])
      subclasses
    end

    def subclasses_of?(klass = nil, type = 'class')
      klass ||= root_object
      subclasses = []
      process_children = proc{ |obj_id| 
        children = @db.find(:super => obj_id)
        children.each do |child|
          if child['type'] == type
            subclasses << child
            break
          else
            process_children.call(child['_id'])
          end
        end
      }
      process_children.call(klass['_id'])
      subclasses.any?
    end

    def submodules_of(klass = nil)
      modules = @db.find(:type => 'module', :super => false)
      submodules = []
      modules.each do |mod|
        submodules << mod
        submodules += subclasses_of(mod, 'module')
      end
      submodules
    end

    def ancestors_of(obj)
      ancestors = []

      while s = obj['super']
        obj = @db.find_one(:_id => s)
        ancestors << obj
      end

      ancestors
    end

    def namespace_treeview(list=nil, names=nil)
      unless list
        puts %[
          <html>
          <head>
            <link rel="stylesheet" href="screen.css" />
            <link rel="stylesheet" href="jquery.treeview.css" />
            <style type="text/css">
              body{ padding: 2em }
            </style>
            <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js"></script>
            <script type="text/javascript" src="jquery.cookie.js"></script>
            <script type="text/javascript" src="jquery.treeview.min.js"></script>
            <script type="text/javascript">
              $(function(){
                $('body > ul').treeview({
                  collapsed: true,
                  animated: "fast"
                });
              });
            </script>  
          </head>
          <body>
        ]
        outer = true

        obj = @db.find_one(:type => 'class', :name => 'Object')
        constants = obj['ivars'].reject{ |k,v| k !~ /^[A-Z]/ }
        names = constants.invert
        classes = @db.find(:type => {:$in => %w[iclass class module]}, :_id => {:$in => constants.values}).to_a.sort_by{ |o| names[o['_id']] || o['name'] }
        list = classes
      end

      puts "<ul>\n"
      list.each{ |obj|
        puts "<li title='#{obj['_id']}'>#{names[obj['_id']] || obj['name']}"

        unless obj['name'] == 'Object'
          constants = obj['ivars'].reject{ |k,v| k !~ /^[A-Z]/ }
          _names = constants.invert
          classes = @db.find(:type => {:$in => %w[iclass class module]}, :_id => {:$in => constants.values}).to_a.sort_by{ |o| _names[o['_id']] || o['name'] }
          if classes.any?
            namespace_treeview(classes, _names)
          end
        end

        puts "</li>"
      }
      puts "</ul>\n"

      if outer
        puts "</body></html>"
      end
    end

    def class_treeview(list=nil)
      unless list
        puts %[
          <html>
          <head>
            <link rel="stylesheet" href="screen.css" />
            <link rel="stylesheet" href="jquery.treeview.css" />
            <style type="text/css">
              body{ padding: 2em }
            </style>
            <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js"></script>
            <script type="text/javascript" src="jquery.cookie.js"></script>
            <script type="text/javascript" src="jquery.treeview.min.js"></script>
            <script type="text/javascript">
              $(function(){
                $('body > ul').treeview({
                  collapsed: true,
                  animated: "fast"
                });
              });
            </script>  
          </head>
          <body>
        ]
        outer = true

        obj = @db.find_one(:type => 'class', :name => 'Object')
        list = [obj]
      end

      puts "<ul>\n"
      list.each{ |obj|
        puts "<li title='#{obj['_id']}'>#{obj['name'] || "#&lt;Class:#{obj['_id']}>"}"

        children = subclasses_of(obj).sort_by{ |o| o['name'] || '' }
        if children.any?
          class_treeview(children)
        end

        puts "</li>"
      }
      puts "</ul>\n"

      if outer
        puts "</body></html>"
      end
    end

    def module_treeview(list=nil)
      unless list
        puts %[
          <html>
          <head>
            <link rel="stylesheet" href="screen.css" />
            <link rel="stylesheet" href="jquery.treeview.css" />
            <style type="text/css">
              body{ padding: 2em }
            </style>
            <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js"></script>
            <script type="text/javascript" src="jquery.cookie.js"></script>
            <script type="text/javascript" src="jquery.treeview.min.js"></script>
            <script type="text/javascript">
              $(function(){
                $('body > ul').treeview({
                  collapsed: true,
                  animated: "fast"
                });
              });
            </script>  
          </head>
          <body>
        ]
        outer = true

        # obj = @db.find_one(:type => 'class', :name => 'Module')
        # list = subclasses_of(obj)
        list = @db.find(:type => 'module', :super => false).sort_by{ |o| o['name'] || '' }
      end

      puts "<ul>\n"
      list.each{ |obj|
        puts "<li title='#{obj['_id']}'>#{(obj['name'] || "#<Module:#{obj['_id']}>").gsub('<', '&lt;')} (#{obj['super']})"

        # children = submodules_of(obj).sort_by{ |o| o['name'] || '' }
        # if children.any?
        #   class_treeview(children)
        # end

        puts "</li>"
      }
      puts "</ul>\n"

      if outer
        puts "</body></html>"
      end
    end

    def filename_treeview(list=nil, key=[:file], cond=nil)
      unless list
        puts %[
          <html>
          <head>
            <link rel="stylesheet" href="screen.css" />
            <link rel="stylesheet" href="jquery.treeview.css" />
            <style type="text/css">
              body{ padding: 2em }
            </style>
            <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js"></script>
            <script type="text/javascript" src="jquery.cookie.js"></script>
            <script type="text/javascript" src="jquery.treeview.min.js"></script>
            <script type="text/javascript">
              $(function(){
                $('body > ul').treeview({
                  collapsed: true,
                  animated: "fast"
                });
              });
            </script>  
          </head>
          <body>
        ]
        outer = true

        files = @db.group(key, cond, {:count=>0}, 'function(d,o){ o.count++ }')
        files = files.sort_by{ |obj| -obj['count'] }

        list = files
      end

      puts "<ul>\n"
      list.first(100).each{ |obj|
        puts "<li>"

        if key.first == :line
          puts "line "
          puts obj[key.first.to_s].to_i

        elsif key.first == :file
          if name = obj[key.first.to_s]
            puts name.split('/').last(4).join('/')
          else
            puts '(unknown)'
          end

        else
          puts obj[key.first.to_s] || '(unknown)'
        end

        case key.first
        when :file
          k = :type
          c = {:file => obj['file']}

        when :type
          c = cond.merge(:type => obj['type'])

          case obj['type']
          when 'object', 'data'
            k = :class_name
          when 'class', 'module'
            k = :name
          when 'string'
            k = :line if cond[:file]
          when 'node'
            # k = :node_type
            k = :line
          end

        when :line
          c = cond.merge(:line => obj['line'])
          k = :node_type

        when :node_type
          # c = cond.merge(:node_type => obj['node_type'])
          # k = :line if cond[:file]
        end

        puts "<span style='float:right'>#{obj['count'].to_i}</span>"

        if k
          objs = @db.group([k], c, {:count=>0}, 'function(d,o){ o.count++ }').sort_by{ |obj| -obj['count'] }
          if objs.any?
            objs.reject!{ |o| o['count'] < 50 } if k == :line
            filename_treeview(objs, [k], c)
          end
        end

        puts "</li>"
      }
      puts "</ul>\n"

      if outer
        puts "</body></html>"
      end
    end
  end
end

__END__

dump = Memprof::Dump.new(:hr)
dump.filename_treeview

# dump = Memprof::Dump.new(:rails)
# dump.module_treeview

# dump = Memprof::Dump.new(:rails)
# dump.class_treeview

# dump = Memprof::Dump.new(:rails)
# dump.namespace_treeview


__END__

dump = Memprof::Dump.new(:rails)
p [dump.db.count, 'objects total']
p [dump.db.find(:type => 'class').count, 'classes']

files = dump.db.group([:file], nil, {:count=>0}, 'function(d,o){ o.count++ }')
files = files.map{ |obj| [obj['file'], obj['count']] }.sort_by{ |file,num| -num.to_i }
files.each{ |file,num| puts "% 8d %s" % [num, file || '(unknown)'] }

lines = dump.db.group([:line], {:file => '/home/aman/homerun/rails/app/controllers/accounts_controller.rb'}, {:count=>0}, 'function(d,o){ o.count++ }')
lines = lines.map{ |obj| [obj['line'], obj['count']] }.sort_by{ |line,num| -num.to_i }
lines.each{ |line,num| puts "% 8d %d" % [num, line] }

types = dump.db.group([:type], {:file => '/home/aman/homerun/rails/app/controllers/accounts_controller.rb'}, {:count=>0}, 'function(d,o){ o.count++ }')
types = types.map{ |obj| [obj['type'], obj['count']] }.sort_by{ |line,num| -num.to_i }
types.each{ |type,num| puts "% 8d %s" % [num, type] }

# p dump.db.find_one(:type => 'class')
# puts dump.db.find(:type => 'class').limit(10).map{|c| c.inspect }.join("\n")

p [:object_subclasses, dump.subclasses_of.map{|o| o['name']}.compact.sort]
p [:module_submodules, dump.submodules_of.map{|o| o['name']}.compact.sort]

obj = dump.db.find_one(:type => 'class', :name => 'Module')
p [:module_ancestors, dump.ancestors_of(obj)]
p [:module_subclasses, dump.subclasses_of(obj)]

obj = dump.db.find_one(:type => 'class', :name => 'Object')
# p obj
constants = obj['ivars'].select{ |k,v| k =~ /^[A-Z]/ }
p [:namespace_list, constants.map{|k,v| k }.sort]
p [:namespace_classes, dump.db.find(:type => {:$in => %w[iclass class module]}, :_id => {:$in => constants.map{|k,v| v }}).map{ |obj| obj['name'] }.sort]

# obj = dump.db.find_one(:type => 'class', :name => 'Object')
# p [:object_ancestors, dump.ancestors_of(obj)]

# obj = dump.db.find_one(:type => 'class', :name => {:$ne=>nil})
# p [dump.ancestors_of(obj)


__END__

{"_id"=>"0x2536450", "type"=>"class", "name"=>nil, "super"=>"0x218c9d0", "super_name"=>nil, "singleton"=>true, "ivars"=>{"__attached__"=>"0x2536478"}, "code"=>3}
