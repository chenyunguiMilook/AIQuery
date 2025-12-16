import Foundation

public struct SymbolGraphFile: Decodable, Sendable {
    public struct Module: Decodable, Sendable {
        public var name: String
    }

    public struct Metadata: Decodable, Sendable {
        public struct FormatVersion: Decodable, Sendable {
            public var major: Int
            public var minor: Int
            public var patch: Int
        }
        public var formatVersion: FormatVersion
    }

    public struct Symbol: Decodable, Sendable {
        public struct Kind: Decodable, Sendable {
            public var identifier: String
            public var displayName: String
        }

        public struct Identifier: Decodable, Sendable {
            public var precise: String
        }

        public struct Names: Decodable, Sendable {
            public var title: String
        }

        public struct Location: Decodable, Sendable {
            public struct Position: Decodable, Sendable {
                public var line: Int
                public var character: Int
            }
            public var uri: String
            public var position: Position
        }

        public struct DeclarationFragment: Decodable, Sendable {
            public var kind: String
            public var spelling: String
        }

        public struct DocComment: Decodable, Sendable {
            public struct Line: Decodable, Sendable {
                public var text: String
            }
            public var lines: [Line]
        }

        public var kind: Kind
        public var identifier: Identifier
        public var names: Names
        public var location: Location?
        public var declarationFragments: [DeclarationFragment]?
        public var docComment: DocComment?

        public var declarationString: String {
            declarationFragments?.map { $0.spelling }.joined() ?? ""
        }

        public var docString: String {
            docComment?.lines.map { $0.text }.joined(separator: "\n") ?? ""
        }
    }

    public struct Relationship: Decodable, Sendable {
        public var source: String
        public var target: String
        public var kind: String
    }

    public var metadata: Metadata
    public var module: Module?
    public var symbols: [Symbol]
    public var relationships: [Relationship]?
}
