# Code Blocks

Here is a fenced code block with a language hint:

```swift
func greet(name: String) -> String {
    return "Hello, \(name)!"
}

let message = greet(name: "World")
print(message)
```

And one without a language:

```
plain code block
no syntax highlighting
just monospace text
```

JavaScript example:

```javascript
function fibonacci(n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

console.log(fibonacci(10));
```

Python example:

```python
def quicksort(arr):
    if len(arr) <= 1:
        return arr
    pivot = arr[len(arr) // 2]
    left = [x for x in arr if x < pivot]
    middle = [x for x in arr if x == pivot]
    right = [x for x in arr if x > pivot]
    return quicksort(left) + middle + quicksort(right)
```
