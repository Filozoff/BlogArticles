import SwiftUI

struct ContentView: View {

    var body: some View {
        VStack {
            UserDetails(name: "Bugs Bunny")
                .accessibilityIdentifierBranch("UserDetails")
        }
        .padding()
        .accessibilityIdentifierBranch("Users")
    }
}

struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
    }
}
