require 'setup'
require 'tsort'
require 'set'
require 'mongo'

$db = Mongo::Connection.new.db('memprof_datasets')

class RefTree
  def initialize
    @dump = $db.collection('stdlib_refs')
  end

  def tsort_each_node
    @dump.find(nil, :fields => [:_id]).each do |obj|
      yield obj['_id']
    end
  end
  def tsort_each_child(node, &blk)
    if obj = @dump.find_one(:_id => node) and obj['refs']
      obj['refs'].each(&blk)
    end
  end

  # include TSort
  def each_strongly_connected_component
    id_map = {}
    stack = []
    tsort_each_node {|node|
      unless id_map.include? node
        each_strongly_connected_component_from(node, id_map, stack) {|c|
          yield c
        }
      end
    }
    nil
  end
  def each_strongly_connected_component_from(node, id_map={}, stack=[])
    minimum_id = node_id = id_map[node] = id_map.size
    stack_length = stack.length
    stack << node

    tsort_each_child(node) {|child|
      if id_map.include? child
        child_id = id_map[child]
        minimum_id = child_id if child_id && child_id < minimum_id
      else
        sub_minimum_id =
          each_strongly_connected_component_from(child, id_map, stack) {|c|
            yield c
          }
        minimum_id = sub_minimum_id if sub_minimum_id < minimum_id
      end
    }

    if node_id == minimum_id
      component = stack.slice!(stack_length .. -1)
      component.each {|n| id_map[n] = nil}
      yield component
    end

    minimum_id
  end
end

@refs   = $db.collection('stdlib_refs')
@groups = $db.collection('stdlib_groups')

if @groups.count == 0
  i = 1
  r = RefTree.new
  r.each_strongly_connected_component do |c|
    @groups.save(:_id => i, :members => c)
    i+=1
  end
  @groups.create_index(:members)
  r = nil
end

if @groups.find(:refs => {:$exists => true}).count == 0
  @groups.find.each do |obj|
    id = obj['_id']

    list = []
    @refs.find(:_id => {:$in => obj['members']}).each do |ref|
      list += ref['refs']
    end
    list.uniq!

    refs = []
    @groups.find({:members => {:$in => list}}, :fields => [:_id]).each do |group|
      refs << group['_id'] unless id == group['_id']
    end

    if refs.any?
      @groups.update({:_id => id}, :$set => {:refs => refs})
    end
  end
end

def dfs(db, obj)
  visited = Set.new
  to_visit = [obj]

  while to_visit.length > 0
    cur = to_visit.pop
    unless visited.include?(cur)
      visited.add(cur)
      if cur_o = db.find_one(:_id => cur)
        yield(cur_o)
        to_visit += cur_o['refs'] if cur_o['refs']
      end
    end
  end
end

@groups.find.each do |obj|
  id = obj['_id']
  s = 0

  dfs(@groups, id) do |child|
    s += child['members'].size
  end

  @groups.update({:_id => id}, :$set => {:size => s})
end
