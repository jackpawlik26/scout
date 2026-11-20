import AppKit
import ScoutCore
import SwiftUI

/// Asks to add a field, or to edit one (drives the field sheet).
struct FieldEditorRequest: Identifiable {
    let id = UUID()
    /// nil: a new field.
    var field: FieldDefinition?
    /// Where to set the new field's first value, if it came from the info panel.
    var path: String?
}

/// Add or edit a field: its name, kind, and for a choice field the choices.
struct FieldEditorSheet: View {
    let request: FieldEditorRequest
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = FieldDefinition.Kind.choice
    @State private var choices = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.field == nil ? "New Field" : "Edit Field").font(.ui(13, .medium))
            TextField("Name (Status, Client, Due…)", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("Kind", selection: $kind) {
                ForEach(FieldDefinition.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(request.field != nil) // changing kind would garble existing values
            if kind == .choice {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choices, one per line").font(.ui(12)).foregroundStyle(Color.textSubtle)
                    TextEditor(text: $choices)
                        .font(.ui(13))
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.hairline))
                }
                Text("Each choice shows in the sidebar with everything set to it.")
                    .font(.ui(12)).foregroundStyle(Color.textSubtle)
            }
            HStack {
                if let field = request.field {
                    Button("Delete Field…", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete “\(field.name)”?", isPresented: $confirmDelete) {
                            Button("Delete Field and Its Values", role: .destructive) {
                                services.deleteField(field.id)
                                dismiss()
                            }
                        } message: {
                            Text("The values you set for it are removed from every file. Files themselves aren’t touched.")
                        }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.field == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (kind == .choice && parsedChoices.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            if let field = request.field {
                name = field.name
                kind = field.kind
                choices = field.choices.joined(separator: "\n")
            } else {
                choices = "To do\nIn progress\nDone"
            }
        }
    }

    private var parsedChoices: [String] {
        var seen = Set<String>()
        return choices.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if var field = request.field {
            field.name = trimmed
            field.choices = kind == .choice ? parsedChoices : []
            services.updateField(field)
        } else {
            services.addField(FieldDefinition(name: trimmed, kind: kind, choices: kind == .choice ? parsedChoices : []))
        }
        dismiss()
    }
}

/// The info panel's Fields card: every field you've added, editable in place.
struct FieldsCard: View {
    let window: BrowserWindowModel?
    let browser: BrowserModel
    let path: String

    var body: some View {
        let services = browser.services
        let fields = services.customizations.fields
        VStack(alignment: .leading, spacing: 6) {
            ForEach(fields) { field in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(field.name).foregroundStyle(Color.textSubtle).lineLimit(1)
                        .frame(width: 84, alignment: .leading)
                        .contextMenu {
                            Button("Edit Field…") { window?.fieldEditor = FieldEditorRequest(field: field) }
                        }
                    FieldValueEditor(field: field, value: services.customizations.value(of: field.id, for: path)) { value in
                        services.setFieldValue(value, of: field.id, for: [path])
                    }
                }
            }
            Button {
                window?.fieldEditor = FieldEditorRequest(path: path)
            } label: {
                Label(fields.isEmpty ? "Add a field (Status, Client, Due…)" : "Add Field", systemImage: "plus")
                    .font(.ui(12)).foregroundStyle(Color.textSubtle)
            }
            .buttonStyle(.plain)
            .help("Your own columns for files and folders, like a spreadsheet. Nothing is written into the files.")
        }
        .font(.ui(13))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RaisedFill(shape: RoundedRectangle(cornerRadius: 10)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hairline))
    }
}

/// One field's value: a menu for choices, a date picker, or a text field.
struct FieldValueEditor: View {
    let field: FieldDefinition
    let value: String?
    let set: (String?) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        switch field.kind {
        case .choice:
            Menu {
                ForEach(field.choices, id: \.self) { choice in
                    Button(choice) { set(choice) }
                }
                if value != nil {
                    Divider()
                    Button("Clear") { set(nil) }
                }
            } label: {
                Text(value ?? "None").foregroundStyle(value == nil ? Color.textSubtle : Color.primary)
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
        case .date:
            HStack(spacing: 6) {
                if let value, let date = FieldDefinition.dayFormat.date(from: value) {
                    DatePicker("", selection: Binding(get: { date }, set: { set(FieldDefinition.dayFormat.string(from: $0)) }),
                               displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field)
                    Button { set(nil) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color.textSubtle).help("Clear")
                } else {
                    Button("Set date") { set(FieldDefinition.dayFormat.string(from: .now)) }
                        .buttonStyle(.plain).foregroundStyle(Color.textSubtle)
                }
            }
        case .text, .number:
            TextField(field.kind == .number ? "0" : "Empty", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { set(text) }
                .onChange(of: isFocused) { _, focused in if !focused { set(text) } }
                .onAppear { text = value ?? "" }
                .onChange(of: value) { _, new in if !isFocused { text = new ?? "" } }
        }
    }
}

/// How a field value reads in a list column.
func fieldDisplay(_ value: String?, _ field: FieldDefinition) -> String {
    guard let value else { return "" }
    switch field.kind {
    case .date:
        return FieldDefinition.dayFormat.date(from: value)?.formatted(date: .abbreviated, time: .omitted) ?? value
    case .number:
        return Double(value).map { $0.formatted(.number) } ?? value
    case .text, .choice:
        return value
    }
}
