import SwiftUI

struct UserDetails: View {

    let name: String

    init(name: String) {
        self.name = name
    }

    var body: some View {
        HStack {
            Image(systemName: "person.circle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40.0)

            VStack(alignment: .leading) {
                Text("Name")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .accessibilityIdentifierLeaf("Label")
                Text(name)
                    .accessibilityIdentifierLeaf("Value")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .cornerRadius(10.0)
    }
}

struct UserSheet_Previews: PreviewProvider {

    static var previews: some View {
        UserDetails(name: "Bugs Bunny")
            .padding()
    }
}
