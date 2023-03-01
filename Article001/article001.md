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

    var userRepository: UserRepository?

    @Published private(set) var isFetchingData = false

    private var currentTask: Task<Void, Error>?

    init() { }

    deinit {
        currentTask?.cancel()
    }

    private func fetchUserData() {
        guard !isFetchingData else { return }
        isFetchingData = true
        currentTask = Task { [weak self] in
            do {
                guard let id = self?.id,
                      let repository = self?.userRepository
                else { return }

                let name = try await repository.fetchName(id: id)
                self?.name = name
            } catch {
                print(error.localizedDescription)
            }

            self?.isFetchingData = false
        }
    }
}

// MARK: - Actions

extension ViewOneViewModel {

    func onAppear() {
        fetchUserData()
    }
}
```

`View`:

```swift
struct ViewOne: View {

    let id: String
    let userRepository: UserRepository

    @StateObject private var viewModel = ViewOneViewModel()

    init(id: String, userRepository: UserRepository) {
        self.id = id
        self.userRepository = userRepository
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Your ID: \(viewModel.id)")
            HStack {
                Text("Name: ")
                TextField("type name", text: $viewModel.name)
                if viewModel.isFetchingData {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .padding()
            .background(.quaternary)
            .cornerRadius(10)
            .disabled(viewModel.isFetchingData)

            NavigationLink("Next View", value: RootView.Page.nextView)
        }
        .padding()
        .onAppear {
            viewModel.id = id
            viewModel.userRepository = userRepository
            viewModel.onAppear()
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
        VStack(alignment: .leading) { (...) }
        .padding()
        .onLoad {
            viewModel.id = id
            viewModel.userRepository = userRepository
        }
        .onAppear {
            viewModel.onAppear()
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

    @Published private(set) var isFetchingData = false

    private var currentTask: Task<Void, Error>?
    private let userRepository: UserRepository

    init(id: String, userRepository: UserRepository) {
        self.id = id
        self.userRepository = userRepository
    }

    deinit {
        currentTask?.cancel()
    }

    private func fetchUserData() {
        guard !isFetchingData else { return }
        isFetchingData = true
        currentTask = Task { [weak self] in
            do {
                guard let id = self?.id,
                      let repository = self?.userRepository
                else { return }

                let name = try await repository.fetchName(id: id)
                self?.name = name
            } catch {
                print(error.localizedDescription)
            }

            self?.isFetchingData = false
        }
    }
}

// MARK: - Actions

extension ViewTwoViewModel {

    func onAppear() {
        fetchUserData()
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
                if viewModel.isFetchingData {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .padding()
            .background(.quaternary)
            .cornerRadius(10)
            .disabled(viewModel.isFetchingData)

            NavigationLink("Next View", value: RootView.Page.nextView)
        }
        .padding()
        .onAppear {
            viewModel.onAppear()
        }
    }
}
```

The `View`'s call looks quite neat too and matches the declarative style:

```swift
ViewTwo(
    viewModel: .init(
        id: "123",
        userRepository: userRepository
    )
)
```

This option is based on [Q&A session notes from SwiftUI Lab at WWDC](https://www.swiftui-lab.com/random-lessons#data-10) (I strongly encourage checking the whole article) and [the discussion from Swift Forum](https://forums.swift.org/t/why-swiftui-state-property-can-be-initialized-inside-init-this-other-way/62772).

It looks more clear than the previous one, however, also comes with limitations. In the case of passing a value type, bear in mind that its mutation does not update the `View` as it is taken only once. Make sure the passed value type is up to date.

That does not affect a reference type or the `Binding`.

## `@StateObject` vs `@ObservedObject`

To choose the right property wrapper it is important to know who owns a `ViewModel`.
The examples above are using `@StateObject` because `ViewOne` and `ViewTwo` are the only owners. `@StateObject` calls it's closure after `View`'s load and keep closure's result until `View` deallocation. That makes `ViewModel` created only once.
Using `@ObservedObject` with a `View` as an owner makes `ViewModel` recreating with every `View`'s redraw. `@ObservedObject` is a good choice as a child `ViewModel`, e.g. for table cell, where the child is held by the parent `ViewModel`.

## Conclusion

Passing dependencies to `ViewModel`s in `SwiftUI` may look very difficult at the first sight, however, it could be easily manageable. It is important to take into consideration all limitations and a data type while passing to a `ViewModel`.
You may find working examples in [my  GitHub repository](https://github.com/Filozoff/BlogArticles/tree/master/Article001).
