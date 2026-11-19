import SwiftUI

// Name the property-wrapper type explicitly to avoid the SDK's State macro overload.
typealias ViewState<Value> = SwiftUI.State<Value>
