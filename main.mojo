from heap import Heap

@parameter
fn comparator[type: AnyType](lhs: type, rhs: type) -> Bool:
    return rebind[Int](lhs) < rebind[Int](rhs)

fn main():
    var heap = Heap[Int, comparator, 4]()