require 'rubygems'
require 'mongo'
require 'pp'
require 'ruby_parser'
require 'ruby2ruby'
require 'unified_ruby'

# $DEBUG=true

class OrderedHash
  %w[ n1 n2 n3 ].each do |node|
    class_eval <<-EOS, __FILE__, __LINE__+1
      def #{node}
        self['#{node}']
      end
    EOS
  end

  alias u1 n1
  alias u2 n2
  alias u3 n3

  alias nd_head  u1
  alias nd_alen  u2
  alias nd_next  u3

  alias nd_cond  u1
  alias nd_body  u2
  alias nd_else  u3

  alias nd_orig  u3

  alias nd_resq  u2
  alias nd_ensr  u3

  alias nd_1st   u1
  alias nd_2nd   u2

  alias nd_stts  u1

  alias nd_entry u3
  alias nd_vid   u1
  alias nd_cflag u2
  alias nd_cval  u3

  alias nd_cnt   u3
  alias nd_tbl   u1

  alias nd_var   u1
  alias nd_ibdy  u2
  alias nd_iter  u3

  alias nd_value u2
  alias nd_aid   u3

  alias nd_lit   u1

  alias nd_frml  u1
  alias nd_rest  u2
  alias nd_opt   u1

  alias nd_recv  u1
  alias nd_args  u3

  alias nd_noex  u1
  alias nd_defn  u3

  alias nd_cfnc  u1
  alias nd_argc  u2

  alias nd_cpath u1
  alias nd_super u3

  alias nd_modl  u1
  alias nd_clss  u1

  alias nd_beg   u1
  alias nd_end   u2
  alias nd_state u3
  alias nd_rval  u2

  alias nd_nth   u2

  alias nd_tag   u1
  alias nd_tval  u2

  def nd_mid
    n2[1..-1].to_sym
  end

  def node_type
    self['node_type'].downcase.to_sym
  end
end

module Memprof
  class Dump
    def initialize(collection_name)
      @@connection ||= Mongo::Connection.new
      @name = collection_name.to_s

      @db = @@connection.db('memprof_datasets').collection(@name)
      # background indexing
      @db.create_index(:type)
      @db.create_index(:super)
      @db.create_index(:file)
      @db.create_index(:class)
      @db.create_index('ivars.__attached__')

      @refs = @@connection.db('memprof_datasets').collection("#{@name}_refs")
      @refs.create_index(:refs)
      @refs.create_index(:refs_size)

      @root_object = @db.find_one(:type => 'class', :name => 'Object')
    end
    attr_reader :name, :db, :refs, :root_object

    def gen_lit(obj)
      if obj.is_a?(String)
        if obj =~ /^0x/
          n = @db.find_one(:_id => obj)
          case n['type']
          when 'regexp'
            Regexp.new(n['data']) # missing //mn options

          when 'string'
            n['data']

          when 'object'
            case n['class_name']
            when 'Range'
              ivars = n['ivars']
              if ivars['excl']
                (ivars['begin']...ivars['end'])
              else
                (ivars['begin']..ivars['end'])
              end

            else
              p [:UNKNOWN, n]
            end

          else
            p [:UNKNOWN, n]
          end

        else
          obj[1..-1].to_sym
        end
      else
        obj
      end
    end

    def gen_sexp_for_proc(obj_or_addr)
      obj = obj_or_addr.respond_to?(:n1) ? obj_or_addr : @db.find_one(:_id => obj_or_addr)

      sexp = [:iter, [:call, nil, :proc, [:arglist]]]
      @masgn_level = 1
      sexp << (obj['nd_var'] ? gen_sexp(obj['nd_var'], []) : nil)
      sexp << gen_sexp(obj['nd_body'], [])
      @masgn_level -= 1
      sexp
    end

    def gen_sexp(obj, locals=nil)
      if locals.nil?
        @masgn_level = 0
        locals = []
      end

      obj = @db.find_one(:_id => obj) unless obj.is_a?(OrderedHash)
      tree = []

      return tree unless obj
      return gen_sexp_for_proc(obj) if obj.has_key?('nd_body')

      if obj['type'] == 'string'
        return obj['data']
      end

      case obj['node_type']
      when 'BLOCK'
        tree << :block
        node = obj
        while node
          tree << gen_sexp(node.nd_head, locals)
          node = @db.find_one(:_id => node.nd_next)
        end
        if @masgn_level == 0 and tree.size == 2
          tree = tree.pop
        end

      when 'FBODY', 'DEFINED'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_head, locals)

      when 'COLON2'
        tree << :colon2
        tree << (obj.nd_head ? gen_sexp(obj.nd_head, locals) : nil)
        tree << obj.nd_mid

      when 'MATCH2', 'MATCH3'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_recv, locals)
        tree << gen_sexp(obj.nd_value, locals)

      when 'BEGIN', 'OPT_N', 'NOT'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_body, locals)

      when 'IF'
        tree << :if
        tree << gen_sexp(obj.nd_cond, locals)
        tree << (obj.nd_body ? gen_sexp(obj.nd_body, locals) : nil)
        tree << (obj.nd_else ? gen_sexp(obj.nd_else, locals) : nil)

      when 'CASE'
        tree << :case
        tree << (obj.nd_head ? gen_sexp(obj.nd_head, locals) : nil)

        node = @db.find_one(:_id => obj.nd_body)
        while node
          tree << gen_sexp(node['_id'], locals)

          if node.node_type == :when
            node = @db.find_one(:_id => node.nd_next)
          else
            break
          end

          unless node
            tree << nil
          end
        end

      when 'WHEN'
=begin
        when_level++;
        if (!inside_case_args && case_level < when_level) { /* when without case, ie, no expr in case */
          if (when_level > 0) when_level--;
          rb_ary_pop(ary); /* reset what current is pointing at */
          node = NEW_CASE(0, node);
          goto again;
        }
        inside_case_args++;
        add_to_parse_tree(self, current, node->nd_head, locals); /* args */
        inside_case_args--;

        if (node->nd_body) {
          add_to_parse_tree(self, current, node->nd_body, locals); /* body */
        } else {
          rb_ary_push(current, Qnil);
        }

        if (when_level > 0) when_level--;
        break;
=end
        tree << :when
        tree << gen_sexp(obj.nd_head, locals)
        tree << (obj.nd_body ? gen_sexp(obj.nd_body, locals) : nil)

      when 'WHILE', 'UNTIL'
        tree << obj['node_type'].downcase.to_sym
        tree << gen_sexp(obj.nd_cond, locals)
        tree << (obj.nd_body ? gen_sexp(obj.nd_body, locals) : nil)
        tree << (obj.n3 == 0 ? true : false)

      when 'BLOCK_PASS'
        tree << :block_pass
        tree << gen_sexp(obj.nd_body, locals)
        tree << gen_sexp(obj.nd_iter, locals)

      when 'ITER', 'FOR'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_iter, locals)
        @masgn_level+=1
        tree << (obj.nd_var ? ![1,2].include?(obj.nd_var) ? gen_sexp(obj.nd_var, locals) : 0 : nil)
        @masgn_level-=1
        tree << gen_sexp(obj.nd_body, locals)

      when 'BREAK', 'NEXT'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_stts) if obj.nd_stts

      when 'YIELD'
        tree << :yield
        tree << gen_sexp(obj.nd_stts, locals) if obj.nd_stts

        node = @db.find_one(:_id => obj.nd_stts)
        tree << true if obj.nd_stts and node and node['node_type'] == 'NEWLINE'
        tree << true if obj.nd_stts and !obj.nd_state and node and %w[ ARRAY ZARRAY ].include?(node['node_type'])

      when 'RESCUE'
        tree << :rescue
        tree << gen_sexp(obj.n1, locals)
        tree << gen_sexp(obj.n2, locals)
        tree << gen_sexp(obj.n3, locals) if obj.n3

      when 'RESBODY'
        tree << :resbody
        tree << (obj.n3 ? gen_sexp(obj.n3, locals) : nil)
        tree << gen_sexp(obj.n2, locals)
        tree << gen_sexp(obj.n1, locals) if obj.n1

      when 'ENSURE'
        tree << :ensure
        tree << gen_sexp(obj.nd_head, locals)
        tree << gen_sexp(obj.nd_ensr, locals) if obj.nd_ensr

      when 'AND', 'OR'
        tree << obj.node_type
        tree << gen_sexp(obj.n1, locals)
        tree << gen_sexp(obj.n2, locals)

      when 'FLIP2', 'FLIP3'
        tree << obj.node_type
        node = @db.find_one(:_id => obj.nd_beg)
        if node['node_type'] == 'LIT'
          tree << [:call, gen_sexp(obj.nd_beg, locals), :==, [:array, [:gvar, :$.]]]
        else
          tree << gen_sexp(obj.nd_beg, locals)
        end

      when 'DOT2', 'DOT3'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_beg, locals)
        tree << gen_sexp(obj.nd_end, locals)

      when 'RETURN'
        tree << :return
        tree << gen_sexp(obj.nd_stts, locals) if obj.nd_stts

      when 'ARGSCAT', 'ARGSPUSH'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_head, locals)
        tree << gen_sexp(obj.nd_body, locals)

      when 'CALL', 'FCALL', 'VCALL'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_recv, locals) if obj.nd_recv and obj['node_type'] != 'FCALL'
        tree << obj.nd_mid
        tree << gen_sexp(obj.nd_args, locals) if obj.nd_args

      when 'SUPER'
        tree << :super
        tree << gen_sexp(obj.nd_args, locals) if obj.nd_args

      when 'BMETHOD'
        tree << :bmethod
        @masgn_level+=1
        proc = @db.find_one(:_id => obj.nd_cval)
        var = @db.find_one(:_id => proc['nd_var'])
        tree << (var ? gen_sexp(var, locals) : nil)
        @masgn_level-=1
        tree << gen_sexp(proc['nd_body'], locals)

      when 'DMETHOD'
        tree << :dmethod
        meth = @db.find_one(:_id => obj.nd_cval)
        tree << meth['mid'][1..-1].to_sym
        tree << gen_sexp(meth['node'], locals)

      when 'METHOD'
        klass = @refs.find_one(:refs => obj['_id'])
        klass = @db.find_one(:_id => klass['_id']) if klass
        name = klass['methods'].find{ |k,v| v == obj['_id'] }.first

        tree << :defn
        tree << name.to_sym
        code = gen_sexp(obj.n2, locals)
        if code.first == :cfunc
          tree << [:scope, [:block, [:args], [:call, nil, :CFUNCTION, [:array, [:lit, code[1]]]]]]
        elsif code.first == :fbody
          tree << code.last
        else
          tree << code
        end

      when 'SCOPE'
        tree << :scope
        tree << gen_sexp(obj.nd_next, obj.nd_tbl.compact.map{ |a| a[1..-1].to_sym })

      when 'OP_ASGN1'
        tree << :op_asgn1
        tree << gen_sexp(obj.nd_recv, locals)

        args = @db.find_one(:_id => obj.nd_args)
        tree << gen_sexp(args.n2, locals)
        tree << obj.nd_mid
        tree << gen_sexp(args.nd_head, locals)

      when 'OP_ASGN2'
        if nxt  = @db.find_one(:_id => obj.nd_next)
          tree << :op_asgn2
          tree << gen_sexp(obj.nd_recv, locals)
          tree << nxt.nd_aid[1..-1].to_sym
          tree << nxt.nd_mid
          tree << gen_sexp(obj.nd_value, locals)
        end

      when 'OP_ASGN_AND', 'OP_ASGN_OR'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_head, locals)
        tree << gen_sexp(obj.nd_value, locals)

      when 'MASGN'
        @masgn_level+=1
        tree << :masgn
        tree << (obj.nd_head ? gen_sexp(obj.nd_head, locals) : nil)
        tree << (obj.nd_args ? obj.nd_args != -1 ? gen_sexp(obj.nd_args, locals) : [:splat] : nil)
        tree << (obj.nd_value ? gen_sexp(obj.nd_value, locals) : nil)
        @masgn_level-=1

      when 'LASGN', 'IASGN', 'DASGN', 'CVASGN', 'CVDECL', 'GASGN'
        tree << obj.node_type
        tree << obj.nd_vid[1..-1].to_sym
        tree << gen_sexp(obj.nd_value, locals) if obj.nd_value

      when 'CDECL'
        tree << :cdecl
        tree << (obj.nd_vid ? obj.nd_vid[1..-1].to_sym : gen_sexp(obj.nd_else, locals))
        tree << gen_sexp(obj.nd_value, locals)

      when 'DASGN_CURR'
        tree << :dasgn_curr
        tree << obj.nd_vid[1..-1].to_sym
        if obj.nd_value
          tree << gen_sexp(obj.nd_value, locals)
          if @masgn_level == 0 and tree.size == 2
            tree = :REMOVE_ME
          end
        elsif @masgn_level == 0
          tree = :REMOVE_ME
        end

      when 'VALIAS'
        tree << :valias
        tree << obj.n1[1..-1].to_sym
        tree << obj.n2[1..-1].to_sym

      when 'ALIAS'
        tree << :alias
        tree << gen_sexp(obj.n1, locals)
        tree << gen_sexp(obj.n2, locals)

      when 'UNDEF'
        tree << :undef
        tree << gen_sexp(obj.nd_value, locals)

      when 'COLON3'
        tree << :colon3
        tree << obj.nd_mid

      when 'HASH'
        tree << :hash

        node = @db.find_one(:_id => obj.nd_head)
        while node
          tree << gen_sexp(node.nd_head, locals)
          node = @db.find_one(:_id => node.nd_next)
          tree << gen_sexp(node.nd_head, locals)
          node = @db.find_one(:_id => node.nd_next)
        end

      when 'ARRAY'
        tree << :array
        node = obj
        while node
          tree << gen_sexp(node.nd_head, locals)
          node = @db.find_one(:_id => node.nd_next)
        end

      when 'DSTR', 'DSYM', 'DXSTR', 'DREGX', 'DREGX_ONCE'
        node = @db.find_one(:_id => obj.nd_next)

        tree << obj.node_type
        tree << gen_lit(obj.nd_lit)

        while node
          tree << gen_sexp(node.nd_head, locals) if node.nd_head
          node = @db.find_one(:_id => node.nd_next)
        end

        if obj['node_type'] =~ /^DREGX/
          tree << obj.nd_cflag
        end

      when 'DEFN', 'DEFS'
        tree << obj.node_type
        if obj.nd_defn
          tree << gen_sexp(obj.nd_recv, locals) if obj['node_type'] == 'DEFS'
          tree << obj.nd_mid
          tree << gen_sexp(obj.nd_defn, locals)
        end

      when 'CLASS', 'MODULE'
        cpath = @db.find_one(:_id => obj.nd_cpath)

        tree << obj.node_type
        if cpath['node_type'] == 'COLON2' && !cpath.nd_vid
          tree << cpath.nd_mid
        else
          tree << gen_sexp(obj.nd_cpath, locals)
        end

        if obj['node_type'] == 'CLASS'
          tree << (obj.nd_super ? gen_sexp(obj.nd_super, locals) : nil)
        end

        tree << gen_sexp(obj.nd_body, locals)

      when 'SCLASS'
        tree << :sclass
        tree << gen_sexp(obj.nd_recv, locals)
        tree << gen_sexp(obj.nd_body, locals)

      when 'ARGS'
        tree << :args
        num = obj.nd_cnt

        tree += locals.first(num)
        rest = locals[num..-1]

        @masgn_level+=1
        node = @db.find_one(:_id => obj.nd_opt)
        while node and rest and rest.any?
          tree << rest.shift
          node = @db.find_one(:_id => node.nd_next)
        end

        if obj.nd_rest
          tree << :"*#{rest ? rest.shift : nil}"
        end

        tree << gen_sexp(obj.nd_opt, locals) if obj.nd_opt
        @masgn_level-=1

      when 'LVAR', 'DVAR', 'IVAR', 'CVAR', 'GVAR', 'CONST', 'ATTRSET'
        tree << obj.node_type
        tree << obj.nd_vid[1..-1].to_sym

      when 'XSTR', 'STR', 'LIT'
        tree << obj.node_type
        tree << gen_lit(obj.nd_lit)

      when 'MATCH'
        tree << :match
        tree << [:lit, gen_lit(obj.nd_lit)]

      when 'NEWLINE'
        tree = gen_sexp(obj.nd_next, locals)

      when 'NTH_REF'
        tree << :nth_ref
        tree << obj.nd_nth

      when 'BACK_REF'
        tree << :back_ref
        tree << obj.nd_mid

      when 'BLOCK_ARG'
        tree << :block_arg
        tree << obj.n1[1..-1].to_sym

      when 'RETRY', 'FALSE', 'NIL', 'SELF', 'TRUE', 'ZARRAY', 'ZSUPER', 'REDO'
        tree << obj.node_type

      when 'SPLAT', 'TO_ARY', 'SVALUE'
        tree << obj.node_type
        tree << gen_sexp(obj.nd_head, locals)

      when 'ATTRASGN'
        tree << :attrasgn
        tree << ((obj.n1 == '0x1' || obj.n1 == 0) ? [:self] : gen_sexp(obj.n1, locals))
        tree << obj.nd_mid
        tree << gen_sexp(obj.n3, locals)

      when 'EVSTR'
        tree << :evstr
        tree << gen_sexp(obj.n2, locals)

      when 'POSTEXE'
        tree << :postexe

      when 'IFUNC', 'CFUNC'
        tree << obj.node_type
        tree << obj.nd_cfnc
        tree << obj.nd_argc

      else
        p [:UNKNOWN, obj['node_type']]
      end

      tree.delete(:REMOVE_ME) if tree.is_a?(Array)
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

  p dump.gen_sexp('0x103e240')

  sexp = dump.gen_sexp('0x525110')
  p sexp

  sexp = Unifier.new.process(sexp)
  puts Ruby2Ruby.new.process(sexp)

  p orig=[:module, :Completion, [:scope, [:block, [:defn, :complete, [:args, :key, :icase, :pat, [:block, [:lasgn, :icase, [:false]], [:lasgn, :pat, [:nil]]]], [:scope, [:block, [:op_asgn_or, [:lvar, :pat], [:lasgn, :pat, [:call, [:const, :Regexp], :new, [:arglist, [:call, [:str, "\\A"], :+, [:arglist, [:call, [:call, [:const, :Regexp], :quote, [:arglist, [:lvar, :key]]], :gsub, [:arglist, [:lit, /\w+\b/], [:str, "\\&\\w*"]]]]], [:lvar, :icase]]]]], [:masgn, [:array, [:lasgn, :canon], [:lasgn, :sw], [:lasgn, :k], [:lasgn, :v], [:lasgn, :cn]], [:to_ary, [:nil]]], [:lasgn, :candidates, [:array]], [:iter, [:call, nil, :each, [:arglist]], [:masgn, [:array, [:lasgn, :k], [:splat, [:lasgn, :v]]]], [:block, [:or, [:if, [:call, [:const, :Regexp], :===, [:arglist, [:lvar, :k]]], [:block, [:lasgn, :kn, [:nil]], [:call, [:lvar, :k], :===, [:arglist, [:lvar, :key]]]], [:block, [:lasgn, :kn, [:if, [:defined, [:call, [:lvar, :k], :id2name, [:arglist]]], [:call, [:lvar, :k], :id2name, [:arglist]], [:lvar, :k]]], [:call, [:lvar, :pat], :===, [:arglist, [:lvar, :kn]]]]], [:next]], [:if, [:call, [:lvar, :v], :empty?, [:arglist]], [:call, [:lvar, :v], :<<, [:arglist, [:lvar, :k]]], nil], [:call, [:lvar, :candidates], :<<, [:arglist, [:array, [:lvar, :k], [:lvar, :v], [:lvar, :kn]]]]]], [:lasgn, :candidates, [:iter, [:call, [:lvar, :candidates], :sort_by, [:arglist]], [:masgn, [:array, [:lasgn, :k], [:lasgn, :v], [:lasgn, :kn]]], [:call, [:lvar, :kn], :size, [:arglist]]]], [:if, [:call, [:call, [:lvar, :candidates], :size, [:arglist]], :==, [:arglist, [:lit, 1]]], [:masgn, [:array, [:lasgn, :canon], [:lasgn, :sw], [:splat]], [:to_ary, [:call, [:lvar, :candidates], :[], [:arglist, [:lit, 0]]]]], [:if, [:call, [:call, [:lvar, :candidates], :size, [:arglist]], :>, [:arglist, [:lit, 1]]], [:block, [:masgn, [:array, [:lasgn, :canon], [:lasgn, :sw], [:lasgn, :cn]], [:to_ary, [:call, [:lvar, :candidates], :shift, [:arglist]]]], [:iter, [:call, [:lvar, :candidates], :each, [:arglist]], [:masgn, [:array, [:lasgn, :k], [:lasgn, :v], [:lasgn, :kn]]], [:block, [:if, [:call, [:lvar, :sw], :==, [:arglist, [:lvar, :v]]], [:next], nil], [:if, [:and, [:call, [:const, :String], :===, [:arglist, [:lvar, :cn]]], [:call, [:const, :String], :===, [:arglist, [:lvar, :kn]]]], [:if, [:call, [:lvar, :cn], :rindex, [:arglist, [:lvar, :kn], [:lit, 0]]], [:block, [:masgn, [:array, [:lasgn, :canon], [:lasgn, :sw], [:lasgn, :cn]], [:array, [:lvar, :k], [:lvar, :v], [:lvar, :kn]]], [:next]], [:if, [:call, [:lvar, :kn], :rindex, [:arglist, [:lvar, :cn], [:lit, 0]]], [:next], nil]], nil], [:call, nil, :throw, [:arglist, [:lit, :ambiguous], [:lvar, :key]]]]]], nil]], [:if, [:lvar, :canon], [:block, [:or, [:call, nil, :block_given?, [:arglist]], [:return, [:array, [:lvar, :key], [:splat, [:lvar, :sw]]]]], [:yield, [:lvar, :key], [:splat, [:lvar, :sw]]]], nil]]]], [:defn, :convert, [:args, :opt, :val, :*, [:block, [:lasgn, :opt, [:nil]], [:lasgn, :val, [:nil]]]], [:scope, [:block, [:lvar, :val]]]]]]]
  puts;puts
  sexp = dump.gen_sexp('0x106c708')
  p sexp

  processor = Unifier.new
  sexp = processor.process(sexp)
  p sexp.to_a

  puts Ruby2Ruby.new.process(sexp)
  puts Ruby2Ruby.new.process(orig)

=begin
  p dump.gen_sexp('0x5774d8')
  p [:defn, :complete, [:args, :typ, :opt, :icase, :"*pat", [:block, [:lasgn, :icase, [:false]]]], [:scope, [:block, [:if, [:call, [:lvar, :pat], :empty?, [:arglist]], [:iter, [:call, nil, :search, [:arglist, [:lvar, :typ], [:lvar, :opt]]], [:lasgn, :sw], [:return, [:array, [:lvar, :sw], [:lvar, :opt]]]], nil], [:call, nil, :raise, [:arglist, [:const, :AmbiguousOption], [:iter, [:call, nil, :catch, [:arglist, [:lit, :ambiguous]]], nil, [:block, [:iter, [:call, nil, :visit, [:arglist, [:lit, :complete], [:lvar, :typ], [:lvar, :opt], [:lvar, :icase], [:splat, [:lvar, :pat]]]], [:masgn, [:array, [:lasgn, :opt], [:splat, [:lasgn, :sw]]]], [:return, [:lvar, :sw]]], [:call, nil, :raise, [:arglist, [:const, :InvalidOption], [:lvar, :opt]]]]]]]]]]

  puts;puts

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

  puts;puts

  dump = Memprof::Dump.new(:railsapp)

  p dump.gen_sexp('0x3062710')
  p [:defn, :b64encode, [:args, :bin, :len, [:block, [:lasgn, :len, [:lit, 60]]]], [:scope, [:block, [:iter, [:call, [:call, nil, :encode64, [:arglist, [:lvar, :bin]]], :scan, [:arglist, [:dregx, ".{1,", [:evstr, [:lvar, :len]], [:str, "}"]]]], nil, [:call, nil, :print, [:arglist, [:back_ref, :&], [:str, "\n"]]]]]]]
=end
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
