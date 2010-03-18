require 'rubygems'
require 'mongo'
require 'pp'
require 'ruby_parser'
require 'ruby2ruby'

class OrderedHash
  def nd_clss
    self['n1']
  end
end

module Memprof
  class Dump
    def initialize(collection_name)
      @@connection ||= Mongo::Connection.new

      @db = @@connection.db('memprof_datasets').collection(collection_name.to_s)
      @db.create_index(:type)
      @db.create_index(:super)
      @db.create_index(:file)
      @db.create_index(:class)
      @db.create_index('ivars.__attached__')

      @refs = @@connection.db('memprof_datasets').collection("#{collection_name}_refs")
      @refs.create_index(:refs)

      @root_object = @db.find_one(:type => 'class', :name => 'Object')
    end
    attr_reader :db, :refs, :root_object

    def gen_sexp(obj, mode=nil)
      obj = @db.find_one(:_id => obj) unless obj.is_a?(OrderedHash)
      tree = []

      return tree unless obj

      if obj['type'] == 'string'
        return obj['data']
      end

      case obj['node_type']
      when 'METHOD'
        tree = gen_sexp(obj['n2'])
        tree = tree.last.last

      when 'CFUNC'
        tree << :cfunc
        tree << obj['n1']
        tree << obj['n2']

      when 'DEFN'
        tree << :defn
        tree << obj['n2'][1..-1].to_sym
        tree += gen_sexp(obj['n3'])

      when 'SCOPE'
        body = gen_sexp(obj['n3'])

        if body[1].first == :args
          args = body.delete_at(1)
          _, num, *rest = args

          args = []
          args.concat obj['n1'].map{ |a| a.to_sym }
          args.concat rest

          rest.each do |arg|
            if arg.is_a?(Array) and arg.first == :lasgn and arg.size == 2
              args.delete(arg)
              idx = args.index(arg.last)
              args[idx] = :"*#{arg[1]}"
              # args[idx+1..-1]=[]
            end
          end

          if body[1] and body[1].is_a?(Array) and body[1].first == :block_arg
            block_arg = body.delete_at(1)
            idx = args.index(block_arg.last.to_sym)
            args.delete(idx)
            args[idx] = :"&#{block_arg.last}"
          end

          found = false
          idx = -1
          args.reject!{ |a|
            idx += 1
            if a.is_a?(Symbol)
              if a.to_s =~ /^(&|\*)/
                found = true
                false
              elsif found or num == 0 or idx > num
                true
              end
            else
              false
            end
          }

          tree << [:args, *args]
        end

        tree << [:scope, body]

      when 'BLOCK'
        tree << :block
        node = obj
        while node
          if node['n1']
            sub = gen_sexp(node['n1']) # nd_head
            sub.shift if sub.first == :block
            tree << sub if sub.any?
          end
          node = @db.find_one(:_id => node['n3']) # nd_next
        end

      when 'NEWLINE'
        tree += gen_sexp(obj['n3'])

      when 'FCALL', 'CALL', 'VCALL'
        tree << :call
        tree << (obj['n1'] ? gen_sexp(obj['n1']) : nil)
        tree << obj['n2'][1..-1].to_sym

        sub = gen_sexp(obj['n3'])
        sub.shift if sub.first == :array

        if sub.first == :splat
          tree << [:arglist, sub]
        else
          tree << [:arglist, *sub]
        end

      when 'ARRAY'
        tree << :array
        tree << gen_sexp(obj['n1'])
        if obj['n3']
          list = gen_sexp(obj['n3'])
          list.shift if list.first == :array
          tree += list
        end

      when 'STR'
        tree << :str
        tree << @db.find_one(:_id => obj['n1'])['data']

      when 'LVAR', 'IVAR', 'DVAR', 'GVAR'
        if obj['node_type'] == 'DVAR'
          tree << :lvar
        else
          tree << obj['node_type'].downcase.to_sym
        end
        tree << obj['n1'][1..-1].to_sym

      when 'ATTRASGN'
        tree << :attrasgn
        tree << (obj['n1'] != 0 ? gen_sexp(obj['n1']) : [:self])
        tree << obj['n2'][1..-1].to_sym
        args = gen_sexp(obj['n3'])
        args[0] = :arglist
        tree << args

      when 'LASGN', 'IASGN', 'DASGN_CURR'
        if obj['node_type'] == 'DASGN_CURR'
          tree << :lasgn
        else
          tree << obj['node_type'].downcase.to_sym
        end

        tree << obj['n1'][1..-1].to_sym
        tree << gen_sexp(obj['n2']) if obj['n2']

      when 'ARGS'
        tree << :args
        tree << obj['n3']
        tree << gen_sexp(obj['n2']) if obj['n2']
        tree << gen_sexp(obj['n1']) if obj['n1']

      when 'IF'
        tree << :if
        tree << gen_sexp(obj['n1'])
        tree << (obj['n2'] ? gen_sexp(obj['n2']) : nil)
        tree << (obj['n3'] ? gen_sexp(obj['n3']) : nil)

      when 'OR', 'RESCUE', 'AND'
        tree << obj['node_type'].downcase.to_sym
        tree << (obj['n1'] ? gen_sexp(obj['n1']) : nil)
        tree << (obj['n2'] ? gen_sexp(obj['n2']) : nil)

      when 'RESBODY'
        tree << :resbody
        tree << (obj['n3'] ? gen_sexp(obj['n3']) : [:array])
        tree << (obj['n2'] ? gen_sexp(obj['n2']) : nil)

      when 'YIELD'
        tree << :yield
        tree << (obj['n1'] ? gen_sexp(obj['n1']) : nil)

      when 'CONST'
        tree << :const << obj['n1'][1..-1].to_sym

      when 'RETURN'
        tree << :return
        tree << gen_sexp(obj['n1']) if obj['n1']

      when 'TRUE', 'FALSE', 'SELF', 'ZSUPER', 'SUPER', 'NIL'
        tree << obj['node_type'].downcase.to_sym

      when 'ZARRAY'
        tree << :array

      when 'DEFINED'
        tree << :defined
        tree << gen_sexp(obj['n1'])

      when 'BLOCK_PASS'
        # tree << :block_pass
        # tree << (obj['n2'] ? gen_sexp(obj['n2']) : nil)
        # tree << (obj['n1'] ? gen_sexp(obj['n1']) : nil)
        # tree << (obj['n3'] ? gen_sexp(obj['n3']) : nil)

        tree = gen_sexp(obj['n3'])
        list = gen_sexp(obj['n1'])
        list.shift if list.first == :array

        if tree.last.is_a?(Array) and tree.last[0] == :arglist
          args = tree.pop
          tree << [:arglist]
          if list.first == :splat
            tree.last << list
          else
            tree.last.concat list
          end
          tree.last << [:block_pass, gen_sexp(obj['n2'])]
        else
          tree += list
          tree << [:block_pass, gen_sexp(obj['n2'])]
        end

      when 'ARGSCAT'
        tree = gen_sexp(obj['n1'])
        tree << [:splat, gen_sexp(obj['n2'])]

      when 'BLOCK_ARG'
        tree << :block_arg
        tree << obj['n1'][1..-1]

      when 'OP_ASGN_OR'
        tree << :op_asgn_or
        tree << (obj['n1'] ? gen_sexp(obj['n1']) : nil)
        tree << (obj['n2'] ? gen_sexp(obj['n2']) : nil)

      when 'SCLASS'
        tree << :sclass
        tree << (obj['n1'] ? gen_sexp(obj['n1']) : nil)
        tree += (obj['n2'] ? gen_sexp(obj['n2']) : nil)

      when 'LIT'
        tree << :lit
        if obj['n1'].is_a?(String)
          if obj['n1'] =~ /^0x/
            n = @db.find_one(:_id => obj['n1'])
            case n['type']
            when 'regexp'
              tree << Regexp.new(n['data']) # missing //mn options
            when 'object'
              case n['class_name']
              when 'Range'
                ivars = n['ivars']
                if ivars['excl']
                  tree << (ivars['begin']...ivars['end'])
                else
                  tree << (ivars['begin']..ivars['end'])
                end
              else
                p [:UNKNOWN, n]
              end
            else
              p [:UNKNOWN, n]
            end
          else
            tree << obj['n1'][1..-1].to_sym
          end
        else
          tree << obj['n1']
        end

      when 'DSTR'
        tree << :dstr
        tree << gen_sexp(obj['n1'])

        list = gen_sexp(obj['n3'])
        list.shift if list.first == :array
        tree += list

      when 'EVSTR'
        tree << :evstr
        tree << gen_sexp(obj['n2'])

      when 'COLON2'
        tree << :colon2
        tree << gen_sexp(obj['n1'])
        tree << obj['n2'][1..-1].to_sym

      when 'SPLAT'
        tree << :splat
        tree << gen_sexp(obj['n1'])

      when 'ITER'
        tree << :iter
        tree << gen_sexp(obj['n3'])
        tree << (obj['n1'] ? gen_sexp(obj['n1']) : nil)
        tree << gen_sexp(obj['n2'])

      when 'HASH'
        tree << :hash

      when 'MASGN'
        tree << :masgn
        tree << (obj['n1'] ? gen_sexp(obj['n1']) : [:array])
        tree.last << [:splat, gen_sexp(obj['n3'])] if obj['n3']
        tree << gen_sexp(obj['n2']) if obj['n2']

      when 'TO_ARY'
        tree << :to_ary
        tree << gen_sexp(obj['n1'])

      when 'WHILE', 'UNTIL'
        tree << obj['node_type'].downcase.to_sym
        tree << gen_sexp(obj['n1'])
        tree << gen_sexp(obj['n2'])
        tree << (obj['n3'] == 0 ? true : false)

      when 'CASE'
        tree << :case
        tree << (obj['n1'] ? gen_sexp(obj['n1']) : nil)

        node = @db.find_one(:_id => obj['n2'])
        while node
          tree << gen_sexp(node['_id'])

          if node['node_type'] == 'WHEN'
            node = @db.find_one(:_id => node['n3'])
          else
            break
          end
        end

      when 'WHEN'
        tree << :when
        tree << gen_sexp(obj['n1'])
        tree << gen_sexp(obj['n2'])

      when 'NOT'
        tree << :not
        tree << gen_sexp(obj['n2'])

      when 'NTH_REF'
        tree << :nth_ref
        tree << obj['n2']

      when 'OP_ASGN1'
        node = @db.find_one(:_id => obj['n3'])

        tree << :op_asgn1
        tree << gen_sexp(obj['n1'])

        list = gen_sexp(node['n2'])
        list[0] = :arglist if list[0] == :array
        tree << list

        tree << obj['n2'][1..-1]

        list = gen_sexp(node['n1'])
        list[0] = :arglist if list[0] == :array
        tree << list

      when 'MATCH2'
        tree << :match2
        tree << gen_sexp(obj['n1'])
        tree << gen_sexp(obj['n2'])

      else
        p [:UNKNOWN, obj['node_type']]
      end

      tree
    end

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

if __FILE__ == $0
  def dump(file, arg)
    File.open(file,'w'){ |f| f.puts PP.pp(arg,'') }
  end

  # dump = Memprof::Dump.new(:base)
  #
  # p dump.gen_sexp('0x1a87d0')
  # p [:defn, :a, [:args], [:scope, [:block, [:call, nil, :puts, [:arglist, [:str, "A"]]]]]]
  #
  # p dump.gen_sexp('0x1a8618')
  # p [:defn, :b, [:args, :a, :b], [:scope, [:block, [:lvar, :a]]]]

  dump = Memprof::Dump.new(:stdlib)

  p dump.gen_sexp('0x35ca90')
  p [:defn, :clone, [:args], [:scope, [:block, [:lasgn, :new, [:zsuper]], [:call, [:lvar, :new], :__setobj__, [:arglist, [:call, [:call, nil, :__getobj__, [:arglist]], :clone, [:arglist]]]], [:lvar, :new]]]]

  puts;puts

  p dump.gen_sexp('0x35cea0')
  p [:defn, :__setobj__, [:args, :obj], [:scope, [:block, [:if, [:call, [:self], :equal?, [:arglist, [:lvar, :obj]]], [:call, nil, :raise, [:arglist, [:const, :ArgumentError], [:str, "cannot delegate to self"]]], nil], [:iasgn, :@_dc_obj, [:lvar, :obj]]]]]

  puts;puts

  p dump.gen_sexp('0x35d508')
  p [:defn, :respond_to?, [:args, :m, :include_private, [:block, [:lasgn, :include_private, [:false]]]], [:scope, [:block, [:if, [:zsuper], [:return, [:true]], nil], [:return, [:call, [:ivar, :@_dc_obj], :respond_to?, [:arglist, [:lvar, :m], [:lvar, :include_private]]]]]]]

  puts;puts

  p dump.gen_sexp('0x35da08')
  p [:defn, :method_missing, [:args, :m, :"*args", :"&block"], [:scope, [:block, [:if, [:call, [:ivar, :@_dc_obj], :respond_to?, [:arglist, [:lvar, :m]]], nil, [:super, [:lvar, :m], [:splat, [:lvar, :args]], [:block_pass, [:lvar, :block]]]], [:call, [:ivar, :@_dc_obj], :__send__, [:arglist, [:lvar, :m], [:splat, [:lvar, :args]], [:block_pass, [:lvar, :block]]]]]]]

  puts;puts

  p dump.gen_sexp('0x519a18')
  p [:defn, :options, [:args], [:scope, [:block, [:op_asgn_or, [:ivar, :@optparse], [:iasgn, :@optparse, [:call, [:const, :OptionParser], :new, [:arglist]]]], [:attrasgn, [:ivar, :@optparse], :default_argv=, [:arglist, [:self]]], [:or, [:call, nil, :block_given?, [:arglist]], [:return, [:ivar, :@optparse]]], [:rescue, [:yield, [:ivar, :@optparse]], [:resbody, [:array, [:const, :ParseError]], [:block, [:call, [:ivar, :@optparse], :warn, [:arglist, [:gvar, :$!]]], [:nil]]]]]]]

  puts;puts

  p dump.gen_sexp('0x51b660')
  p [:defn, :options=, [:args, :opt], [:scope, [:block, [:if, [:iasgn, :@optparse, [:lvar, :opt]], nil, [:sclass, [:self], [:scope, [:block, [:call, nil, :undef_method, [:arglist, [:lit, :options]]], [:call, nil, :undef_method, [:arglist, [:lit, :options=]]]]]]]]]]

  puts;puts

  p dump.gen_sexp('0x528c98')
  p [:defn, :inspect, [:args], [:scope, [:block, [:dstr, "#<", [:evstr, [:call, [:call, [:self], :class, [:arglist]], :to_s, [:arglist]]], [:str, ": "], [:evstr, [:call, [:call, nil, :args, [:arglist]], :join, [:arglist, [:str, " "]]]], [:str, ">"]]]]]

  puts;puts

  p dump.gen_sexp('0x529a30')
  p [:defn, :reason, [:args], [:scope, [:block, [:or, [:ivar, :@reason], [:colon2, [:call, [:self], :class, [:arglist]], :Reason]]]]]

  puts;puts

  p dump.gen_sexp('0x572af0')
  p [:defn, :environment, [:args, :env, [:block, [:lasgn, :env, [:call, [:const, :File], :basename, [:arglist, [:gvar, :$0], [:str, ".*"]]]]]], [:scope, [:block, [:or, [:lasgn, :env, [:or, [:call, [:const, :ENV], :[], [:arglist, [:lvar, :env]]], [:call, [:const, :ENV], :[], [:arglist, [:call, [:lvar, :env], :upcase, [:arglist]]]]]], [:return]], [:call, nil, :require, [:arglist, [:str, "shellwords"]]], [:call, nil, :parse, [:arglist, [:splat, [:call, [:const, :Shellwords], :shellwords, [:arglist, [:lvar, :env]]]]]]]]]

  puts;puts

  p dump.gen_sexp('0x575110')
  p [:defn, :load, [:args, :filename, [:block, [:lasgn, :filename, [:nil]]]], [:scope, [:block, [:rescue, [:op_asgn_or, [:lvar, :filename], [:lasgn, :filename, [:call, [:const, :File], :expand_path, [:arglist, [:call, [:const, :File], :basename, [:arglist, [:gvar, :$0], [:str, ".*"]]], [:str, "~/.options"]]]]], [:resbody, [:array], [:return, [:false]]]], [:rescue, [:block, [:call, nil, :parse, [:arglist, [:splat, [:iter, [:call, [:call, [:const, :IO], :readlines, [:arglist, [:lvar, :filename]]], :each, [:arglist]], [:lasgn, :s], [:call, [:lvar, :s], :chomp!, [:arglist]]]]]], [:true]], [:resbody, [:array, [:colon2, [:const, :Errno], :ENOENT], [:colon2, [:const, :Errno], :ENOTDIR]], [:false]]]]]]

  puts;puts

  p dump.gen_sexp('0x594128')
  p [:defn, :getopts, [:args, :"*args"], [:scope, [:block, [:lasgn, :argv, [:if, [:call, [:const, :Array], :===, [:arglist, [:call, [:lvar, :args], :first, [:arglist]]]], [:call, [:lvar, :args], :shift, [:arglist]], [:call, nil, :default_argv, [:arglist]]]], [:masgn, [:array, [:lasgn, :single_options], [:splat, [:lasgn, :long_options]]], [:splat, [:lvar, :args]]], [:lasgn, :result, [:hash]], [:if, [:lvar, :single_options], [:iter, [:call, [:lvar, :single_options], :scan, [:arglist, [:lit, /(.)(:)?/]]], [:masgn, [:array, [:lasgn, :opt], [:lasgn, :val]]], [:if, [:lvar, :val], [:block, [:attrasgn, [:lvar, :result], :[]=, [:arglist, [:lvar, :opt], [:nil]]], [:call, nil, :define, [:arglist, [:dstr, "-", [:evstr, [:lvar, :opt]], [:str, " VAL"]]]]], [:block, [:attrasgn, [:lvar, :result], :[]=, [:arglist, [:lvar, :opt], [:false]]], [:call, nil, :define, [:arglist, [:dstr, "-", [:evstr, [:lvar, :opt]]]]]]]], nil], [:iter, [:call, [:lvar, :long_options], :each, [:arglist]], [:lasgn, :arg], [:block, [:masgn, [:array, [:lasgn, :opt], [:lasgn, :val]], [:to_ary, [:call, [:lvar, :arg], :split, [:arglist, [:str, ":"], [:lit, 2]]]]], [:if, [:lvar, :val], [:block, [:attrasgn, [:lvar, :result], :[]=, [:arglist, [:lvar, :opt], [:if, [:call, [:lvar, :val], :empty?, [:arglist]], [:nil], [:lvar, :val]]]], [:call, nil, :define, [:arglist, [:dstr, "--", [:evstr, [:lvar, :opt]], [:str, " VAL"]]]]], [:block, [:attrasgn, [:lvar, :result], :[]=, [:arglist, [:lvar, :opt], [:false]]], [:call, nil, :define, [:arglist, [:dstr, "--", [:evstr, [:lvar, :opt]]]]]]]]], [:call, nil, :parse_in_order, [:arglist, [:lvar, :argv], [:call, [:lvar, :result], :method, [:arglist, [:lit, :[]=]]]]], [:lvar, :result]]]]

  puts;puts

  p dump.gen_sexp('0x10011b0')
  p [:defn, :parse, [:args, :"*argv"], [:scope, [:block, [:if, [:and, [:call, [:call, [:lvar, :argv], :size, [:arglist]], :==, [:arglist, [:lit, 1]]], [:call, [:const, :Array], :===, [:arglist, [:call, [:lvar, :argv], :[], [:arglist, [:lit, 0]]]]]], [:lasgn, :argv, [:call, [:call, [:lvar, :argv], :[], [:arglist, [:lit, 0]]], :dup, [:arglist]]], nil], [:call, nil, :parse!, [:arglist, [:lvar, :argv]]]]]]

  puts;puts

  p dump.gen_sexp('0x101b2b8')
  p [:defn, :on_tail, [:args, :"*opts", :"&block"], [:scope, [:block, [:call, nil, :define_tail, [:arglist, [:splat, [:lvar, :opts]], [:block_pass, [:lvar, :block]]]], [:self]]]]

  puts;puts

  p dump.gen_sexp('0x22f7dc8')
  p [:defn, :set_error, [:args, :ex, :backtrace, [:block, [:lasgn, :backtrace, [:false]]]], [:scope, [:block, [:case, [:lvar, :ex], [:when, [:array, [:colon2, [:const, :HTTPStatus], :Status]], [:block, [:if, [:call, [:const, :HTTPStatus], :error?, [:arglist, [:call, [:lvar, :ex], :code, [:arglist]]]], [:iasgn, :@keep_alive, [:false]], nil], [:attrasgn, [:self], :status=, [:arglist, [:call, [:lvar, :ex], :code, [:arglist]]]]]], [:block, [:iasgn, :@keep_alive, [:false]], [:attrasgn, [:self], :status=, [:arglist, [:colon2, [:const, :HTTPStatus], :RC_INTERNAL_SERVER_ERROR]]]]], [:attrasgn, [:ivar, :@header], :[]=, [:arglist, [:str, "content-type"], [:str, "text/html"]]], [:if, [:call, nil, :respond_to?, [:arglist, [:lit, :create_error_page]]], [:block, [:call, nil, :create_error_page, [:arglist]], [:return]], nil], [:if, [:ivar, :@request_uri], [:masgn, [:array, [:lasgn, :host], [:lasgn, :port]], [:array, [:call, [:ivar, :@request_uri], :host, [:arglist]], [:call, [:ivar, :@request_uri], :port, [:arglist]]]], [:masgn, [:array, [:lasgn, :host], [:lasgn, :port]], [:array, [:call, [:ivar, :@config], :[], [:arglist, [:lit, :ServerName]]], [:call, [:ivar, :@config], :[], [:arglist, [:lit, :Port]]]]]], [:iasgn, :@body, [:str, ""]], [:call, [:ivar, :@body], :<<, [:arglist, [:dstr, "  <!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0//EN\">\n  <HTML>\n    <HEAD><TITLE>", [:evstr, [:call, [:const, :HTMLUtils], :escape, [:arglist, [:ivar, :@reason_phrase]]]], [:str, "</TITLE></HEAD>\n    <BODY>\n      <H1>"], [:evstr, [:call, [:const, :HTMLUtils], :escape, [:arglist, [:ivar, :@reason_phrase]]]], [:str, "</H1>\n      "], [:evstr, [:call, [:const, :HTMLUtils], :escape, [:arglist, [:call, [:lvar, :ex], :message, [:arglist]]]]], [:str, "\n      <HR>\n"]]]], [:if, [:and, [:lvar, :backtrace], [:gvar, :$DEBUG]], [:block, [:call, [:ivar, :@body], :<<, [:arglist, [:dstr, "backtrace of `", [:evstr, [:call, [:const, :HTMLUtils], :escape, [:arglist, [:call, [:call, [:lvar, :ex], :class, [:arglist]], :to_s, [:arglist]]]]], [:str, "' "]]]], [:call, [:ivar, :@body], :<<, [:arglist, [:dstr, "", [:evstr, [:call, [:const, :HTMLUtils], :escape, [:arglist, [:call, [:lvar, :ex], :message, [:arglist]]]]]]]], [:call, [:ivar, :@body], :<<, [:arglist, [:str, "<PRE>"]]], [:iter, [:call, [:call, [:lvar, :ex], :backtrace, [:arglist]], :each, [:arglist]], [:lasgn, :line], [:call, [:ivar, :@body], :<<, [:arglist, [:dstr, "\t", [:evstr, [:lvar, :line]], [:str, "\n"]]]]], [:call, [:ivar, :@body], :<<, [:arglist, [:str, "</PRE><HR>"]]]], nil], [:call, [:ivar, :@body], :<<, [:arglist, [:dstr, "      <ADDRESS>\n       ", [:evstr, [:call, [:const, :HTMLUtils], :escape, [:arglist, [:call, [:ivar, :@config], :[], [:arglist, [:lit, :ServerSoftware]]]]]], [:str, " at\n       "], [:evstr, [:lvar, :host]], [:str, ":"], [:evstr, [:lvar, :port]], [:str, "\n      </ADDRESS>\n    </BODY>\n  </HTML>\n"]]]]]]]

  puts;puts

  p dump.gen_sexp('0x22fe6a0')
  p [:defn, :setup_header, [:args], [:scope, [:block, [:op_asgn_or, [:ivar, :@reason_phrase], [:iasgn, :@reason_phrase, [:call, [:const, :HTTPStatus], :reason_phrase, [:arglist, [:ivar, :@status]]]]], [:op_asgn1, [:ivar, :@header], [:arglist, [:str, "server"]], :"||", [:call, [:ivar, :@config], :[], [:arglist, [:lit, :ServerSoftware]]]], [:op_asgn1, [:ivar, :@header], [:arglist, [:str, "date"]], :"||", [:call, [:call, [:const, :Time], :now, [:arglist]], :httpdate, [:arglist]]], [:if, [:call, [:ivar, :@request_http_version], :<, [:arglist, [:str, "1.0"]]], [:block, [:iasgn, :@http_version, [:call, [:const, :HTTPVersion], :new, [:arglist, [:str, "0.9"]]]], [:iasgn, :@keep_alive, [:false]]], nil], [:if, [:call, [:ivar, :@request_http_version], :<, [:arglist, [:str, "1.1"]]], [:if, [:call, nil, :chunked?, [:arglist]], [:block, [:iasgn, :@chunked, [:false]], [:lasgn, :ver, [:call, [:ivar, :@request_http_version], :to_s, [:arglist]]], [:lasgn, :msg, [:dstr, "chunked is set for an HTTP/", [:evstr, [:lvar, :ver]], [:str, " request. (ignored)"]]], [:call, [:ivar, :@logger], :warn, [:arglist, [:lvar, :msg]]]], nil], nil], [:if, [:or, [:call, [:ivar, :@status], :==, [:arglist, [:lit, 304]]], [:or, [:call, [:ivar, :@status], :==, [:arglist, [:lit, 204]]], [:call, [:const, :HTTPStatus], :info?, [:arglist, [:ivar, :@status]]]]], [:block, [:call, [:ivar, :@header], :delete, [:arglist, [:str, "content-length"]]], [:iasgn, :@body, [:str, ""]]], [:if, [:call, nil, :chunked?, [:arglist]], [:block, [:attrasgn, [:ivar, :@header], :[]=, [:arglist, [:str, "transfer-encoding"], [:str, "chunked"]]], [:call, [:ivar, :@header], :delete, [:arglist, [:str, "content-length"]]]], [:if, [:match2, [:lit, /^multipart\/byteranges/], [:call, [:ivar, :@header], :[], [:arglist, [:str, "content-type"]]]], [:call, [:ivar, :@header], :delete, [:arglist, [:str, "content-length"]]], [:if, [:call, [:call, [:ivar, :@header], :[], [:arglist, [:str, "content-length"]]], :nil?, [:arglist]], [:if, [:call, [:ivar, :@body], :is_a?, [:arglist, [:const, :IO]]], nil, [:attrasgn, [:ivar, :@header], :[]=, [:arglist, [:str, "content-length"], [:if, [:ivar, :@body], [:call, [:ivar, :@body], :size, [:arglist]], [:lit, 0]]]]], nil]]]], [:if, [:call, [:call, [:ivar, :@header], :[], [:arglist, [:str, "connection"]]], :==, [:arglist, [:str, "close"]]], [:iasgn, :@keep_alive, [:false]], [:if, [:call, nil, :keep_alive?, [:arglist]], [:if, [:or, [:call, nil, :chunked?, [:arglist]], [:call, [:ivar, :@header], :[], [:arglist, [:str, "content-length"]]]], [:attrasgn, [:ivar, :@header], :[]=, [:arglist, [:str, "connection"], [:str, "Keep-Alive"]]], nil], [:attrasgn, [:ivar, :@header], :[]=, [:arglist, [:str, "connection"], [:str, "close"]]]]], [:if, [:lasgn, :location, [:call, [:ivar, :@header], :[], [:arglist, [:str, "location"]]]], [:if, [:ivar, :@request_uri], [:attrasgn, [:ivar, :@header], :[]=, [:arglist, [:str, "location"], [:call, [:ivar, :@request_uri], :merge, [:arglist, [:lvar, :location]]]]], nil], nil]]]]
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
