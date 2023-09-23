from memory.unsafe import Pointer
from utils.vector import DynamicVector

alias Comparator = fn[type: AnyType] (type, type) -> Bool

@always_inline
fn _parent_index[branching_factor: Int](index: Int) -> Int:
    return (index - 1) // branching_factor

@always_inline
fn _last_child_index[branching_factor: Int](index: Int) -> Int:
    return index * branching_factor + branching_factor

@always_inline
fn _DynamicVector_begin[type: AnyType](vec: DynamicVector[type]) -> Pointer[type]:
    return vec.data

@always_inline
fn _DynamicVector_end[type: AnyType](vec: DynamicVector[type]) -> Pointer[type]:
    return vec.data.offset(len(vec))

# TODO: Should go away with traits
@always_inline
fn bool_to_int(b: Bool) -> Int:
    var simd = SIMD[DType.bool, 8](False)
    simd[0] = b

    return rebind[Int](simd)

@always_inline
fn _largest_child[type: AnyType, branching_factor: Int, comparator: Comparator](first_child: Pointer[type]) -> Pointer[type]:
    @parameter
    if branching_factor == 1:
        return first_child
    @parameter
    if branching_factor == 2:
        return first_child + bool_to_int(comparator[type](first_child[0], first_child[1]))

    alias half_branching_factor = branching_factor // 2
    let first_half_largest = _largest_child[type, half_branching_factor, comparator](first_child)
    let second_half_largest = _largest_child[type, branching_factor - half_branching_factor, comparator](first_child + half_branching_factor)
    if comparator[type](first_half_largest.load(), second_half_largest.load()):
        return second_half_largest

    return first_half_largest

@always_inline
fn _largest_child[type: AnyType, branching_factor: Int, comparator: Comparator](first_child: Pointer[type], num_children: Int) -> Pointer[type]:
    @parameter
    if branching_factor == 2:
        return first_child
    @parameter
    if branching_factor == 4:
        if num_children == 1:
            return first_child
        if num_children == 2:
            return first_child + bool_to_int(comparator[type](first_child[0], first_child[1]))
        let largest = first_child + bool_to_int(comparator[type](first_child[0], first_child[1]))
        if comparator[type](largest.load(), first_child[2]):
            return first_child + 2
        return largest

    let half = num_children // 2
    let first_half_largest = _largest_child[type, branching_factor, comparator](first_child, half)
    let second_half_largest = _largest_child[type, branching_factor, comparator](first_child + half, num_children - half)
    if comparator[type](first_half_largest.load(), second_half_largest.load()):
        return second_half_largest
    return first_half_largest

fn heap_pop[type: AnyType, comparator: Comparator, branching_factor: Int](begin: Pointer[type], end: Pointer[type]):
    let length = end.__as_index() - begin.__as_index() - 1
    let item = end[-1]
    var index = 0

    while True:
        let last_child = _last_child_index[branching_factor](index)
        let first_child = last_child - (branching_factor - 1)
        if last_child < length:
            let largest_child = _largest_child[type, branching_factor, comparator](begin.offset(first_child))
            if not comparator[type](item, largest_child.load()):
                break
            begin.offset(index).store(largest_child.load())
            index = largest_child.__as_index() - begin.__as_index()
        elif first_child < length:
            let largest_child = _largest_child[type, branching_factor, comparator](begin.offset(first_child), length - first_child)
            if comparator[type](item, largest_child.load()):
                begin.offset(index).store(largest_child.load())
                index = largest_child.__as_index() - begin.__as_index()
            break
        else:
            break

    begin.offset(index).store(item)

fn heap_push[type: AnyType, comparator: Comparator, branching_factor: Int](begin: Pointer[type], end: Pointer[type]):
    var index = end.__as_index() - begin.__as_index() - 1
    let item = end[-1]

    while index:
        let parent = _parent_index[branching_factor](index)
        if not comparator[type](begin[parent], item):
            break
        begin.offset(index).store(begin[parent])
        index = parent

    begin.offset(index).store(item)

struct Heap[type: AnyType, comparator: Comparator, branching_factor: Int]:
    var _queue: DynamicVector[type]

    fn __init__(inout self):
        self._queue = DynamicVector[type]()

    @always_inline
    fn clear(inout self):
        self._queue.clear()

    @always_inline
    fn reserve(inout self, capacity: Int):
        self._queue.reserve(capacity + 1)

    @always_inline
    fn size(self) -> Int:
        return len(self._queue)

    @always_inline
    fn __len__(self) -> Int:
        return self.size()

    @always_inline
    fn empty(self) -> Bool:
        return self.size() == 0

    @always_inline
    fn insert(inout self, item: type):
        self._queue.push_back(item)
        let beg = _DynamicVector_begin(self._queue)
        let end = _DynamicVector_end(self._queue)
        heap_push[type, comparator, branching_factor](beg, end)

    @always_inline
    fn pop(inout self) -> type:
        let ret = self._queue[0]
        let beg = _DynamicVector_begin(self._queue)
        let end = _DynamicVector_end(self._queue)
        heap_pop[type, comparator, branching_factor](beg, end)
        self._queue.pop_back()

        return ret
