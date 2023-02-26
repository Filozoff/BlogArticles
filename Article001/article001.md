# Passing dependencies to ViewModel in SwiftUI

When taking the first steps with SwiftUI, this runtime warning is very often encountered:

>"Accessing StateObject's object without being installed on a View. This will create a new instance each time."

... which can be frustrating at the beginning, especially for devs who come from "`UIKit` world".  Paying attention to this message is strongly recommended, because that highlighted code may not only impact the performance but the logic as well.

The way how the dependencies are passed defines API design and construction of Unit Tests.

So then, how to pass dependency to a `ViewModel` safely and reliably?

See the proposals below.

## Through `onAppear`

One of the solutions is passing dependencies when we are 100% sure that it happens after a view’s creation: through `onAppear` modifier. Let’s take a look at the code:

`ViewModel`:

```swift
@MainActor
class ViewOneViewModel: ObservableObject {

    @Published var id = "nil"
    @Published var name = ""

    var nameRepository: NameRepository?

    init() { }
}
```

`View`:

```swift
struct ViewOne: View {

    let id: String
    let name: String
    let nameRepository: NameRepository

    @StateObject private var viewModel = ViewOneViewModel()

    init(id: String, name: String, nameRepository: NameRepository) {
        self.id = id
        self.name = name
        self.nameRepository = nameRepository
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Your ID: \(viewModel.id)")
            HStack {
                Text("Name:")
                TextField("Type name", text: $viewModel.name)
            }
        }
        .padding()
        .onAppear {
            viewModel.id = id
            viewModel.name = name
            viewModel.nameRepository = nameRepository
        }
    }
}
```

At the current stage, the `View` resets its state with every “appear” action, e.g. when navigating back or switching tabs. Ideally would be, to assign properties only "on `View` loaded" event. Due to the lack of such a modifier in `SwiftUI`, it is required to create a custom one to tackle this issue:

```swift
struct OnLoadViewModifier: ViewModifier {

    typealias Action = () -> ()

    @State private var isLoaded = false

    private let action: Action

    init(action: @escaping Action) {
        self.action = action
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isLoaded else { return }
                isLoaded = true
                action()
            }
    }
}

extension View {

    func onLoad(perform action: @escaping OnLoadViewModifier.Action) -> some View {
        modifier(OnLoadViewModifier(action: action))
    }
}
```

Updated `ViewOne` with a new modifier:

```swift
struct ViewOne: View {

    (...)

    var body: some View {
        VStack(alignment: .leading) {
            Text("Your ID: \(viewModel.id)")
            HStack {
                Text("Name:")
                TextField("Type name", text: $viewModel.name)
            }
        }
        .padding()
        .onLoad {
            viewModel.id = id
            viewModel.name = name
            viewModel.nameRepository = nameRepository
        }
    }
}
```

As you may see, with this solution `ViewOneViewModel` requires to have either pre-defined, optional, or late init values. `ViewOne`'s properties are used to be passed further to `ViewModel` only. That duplication creates API pollution which may lead to the wrong adaptation by other developers e.g. by using properties from a `View` instead of a `ViewModel`. Besides, the code requires more attention during its maintenance.

## Through constructor

This solution is based on passing dependencies when `@StateObject` property wrapper calls its closure (i.e. when a `View` is created).

`ViewModel`:

```swift
@MainActor
class ViewTwoViewModel: ObservableObject {

    @Published var name = ""

    let id: String
    let nameRepository: NameRepository

    init(id: String, name: String, nameRepository: NameRepository) {
        self.id = id
        self.name = name
        self.nameRepository = nameRepository
    }
}
```

`View`:

```swift
typealias ReturnClosure<T> = () -> T

struct ViewTwo: View {

    @StateObject private var viewModel: ViewTwoViewModel

    init(viewModel: @escaping @autoclosure ReturnClosure<ViewTwoViewModel>) {
        _viewModel = .init(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Your ID: \(viewModel.id)")
            HStack {
                Text("Name: ")
                TextField("type name", text: $viewModel.name)
            }
        }
        .padding()
    }
}
```

The `View`'s call looks quite neat too and matches the declarative style:

```swift
ViewTwo(
    viewModel: .init(
        id: "123",
        name: "Tom",
        nameRepository: nameRepository
    )
)
```

This option is based on [Q&A session notes from SwiftUI Lab at WWDC](https://www.swiftui-lab.com/random-lessons#data-10) (I strongly encourage checking the whole article) and [the discussion from Swift Forum](https://forums.swift.org/t/why-swiftui-state-property-can-be-initialized-inside-init-this-other-way/62772).

It looks more clear than the previous one, however, also comes with limitations. In the case of passing a value type, bear in mind that its mutation does not update the `View` as it is taken only once. Make sure the passed value type is up to date.

That does not affect a reference type or the `Binding`.

## Conclusion

Passing dependencies to `ViewModel`s in `SwiftUI` may look very difficult at the first sight, however, it could be easily manageable. It is important to take into consideration all limitations and a data type while passing to a `ViewModel`.
You may find working examples in [my  GitHub repository](https://github.com/Filozoff/BlogArticles/tree/master/Article001).
