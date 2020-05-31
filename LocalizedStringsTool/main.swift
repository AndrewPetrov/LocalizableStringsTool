//
//  main.swift
//  LocalizedStringsTool
//
//  Created by AndrewPetrov on 9/19/19.
//  Copyright © 2019 AndrewPetrov. All rights reserved.
//

import Cocoa
import Foundation

/*
 + получить текущую папку или прочитать путь
 + получить список всех .swift, .h, .m файлов
 + прочитать из каждого строки
 + составить сет из этих ключей “usedKeys”
 + получить список файлов .strings
 + составить массив из ключей “availableKeys” для каждого языка
 + “usedKeys” -   “availableKeys” = ключи без перевода (точно)
 + ключи без перевода (возможно)
 + “availableKeys” - “usedKeys” = неиспользуемые ключи
 + дублирование переводов
 + поддержка обж с
 + добавить все исключения из моно
 + оптимизация потребления памяти
 + указание пути
 + получить инфу со stringdict
 + сортировка как в файле с переводами
 + сепараторы секций переводов как в оригинале
 + добавить дефольные настройки
 + загрузка настроек из файла
 + разные ключи в разных файлах перевода
 - добавить все исключения из обычных проектов
 - рефакторинг
 - кастомные правила для ключей
 + кастомные исключения
 - csv export
 + отображать прогресс

 */

// MARK: - SETTINGS

struct Settings: Decodable {
    let projectRootFolderPath: String

    let unusedTranslations: Bool
    let translationDuplication: Bool
    let untranslatedKeys: Bool
    let allUntranslatedStrings: Bool
    let differentKeysInTranslations: Bool

    let shouldAnalyzeSwift: Bool
    let shouldAnalyzeObjC: Bool

    let customObjCPatternPrefixes: [String]

    let objCExceptions: [String]
    let swiftExceptions: [String]
    let folderExcludedNames: [String]

}

// PROGRESS CALCULATION

let startTime = Date()
var commonFilesCount = 0
var currentFilesCountHandled = 0

var settings: Settings = readPlist()

//let executableName = CommandLine.arguments[0] as NSString
//print(executableName)

//let argCount = CommandLine.argc

var swiftFilePathSet = Set<String>()
var hFilePathSet = Set<String>()
var mFilePathSet = Set<String>()
var localizableFilePathDict = [String]()
var localizableDictFilePathDict = [String]()

getAllFilesPaths(
    swiftFilePathSet: &swiftFilePathSet,
    hFilePathSet: &hFilePathSet,
    mFilePathSet: &mFilePathSet,
    localizableFilePathDict: &localizableFilePathDict,
    localizableDictFilePathDict: &localizableDictFilePathDict
)

var swiftKeys = Set<String>()
var objCKeys = Set<String>()
var allSwiftStrings = Set<String>()
var allSwiftProbablyKeys = Set<String>()
var allObjCProbablyKeys = Set<String>()
var allProbablyKeys = Set<String>()

typealias TranslationPair = (key: String, translation: String)
struct Section {
    let name: String
    var translations: [TranslationPair]
}

//                      language
var localizationsDict = [String: [Section]]()

let keyVariableCaptureName = "KEY"
let translationVariableCaptureName = "TRANSLATION"
let translationSectionVariableCaptureName = "SECTION"
let anyStringVariableCaptureName = "ANYSTRING"

let swiftKeyPattern = #""(?<"# + keyVariableCaptureName + #">\S*)".localized\(\)"#
let swiftOldKeyPattern = #"lang\("(?<"# + keyVariableCaptureName + #">\S*)"\)"#
//"# + + #"
let objCKeyPattern = getObjCKeyPattern(settings: settings)
//    #"(lang|title|subtitle|advice|buttonTitle|rescanTitle|rescanSubtitle)\(@"(?<"# + keyVariableCaptureName + #">\S*)"\)"#

func getObjCKeyPattern(settings: Settings) -> String {
    var pattern = #"("#

    for prefix in settings.customObjCPatternPrefixes {
        pattern += prefix + #"|"#
    }
    pattern.removeLast()

    pattern += #")\(@"(?<"# + keyVariableCaptureName + #">\S*)"\)"#

    print(pattern)

    print(#"(lang|title|subtitle|advice|buttonTitle|rescanTitle|rescanSubtitle)\(@"(?<"# + keyVariableCaptureName + #">\S*)"\)"#)

    return pattern
}

let localizedSectionPattern = #"(?<"# + translationSectionVariableCaptureName + #">(\/\*([^\*\/])+\*\/)|(\/\/.+\n+)+)*\n*(("(?<"# + keyVariableCaptureName + #">\S*)" = "(?<"# + translationVariableCaptureName + #">(.*)\s?)")*;)+"#

var allObjCStringPattern = ""

settings.objCExceptions.forEach { exception in
    allObjCStringPattern += #"(?<!("# + exception + #"))"#
}

allObjCStringPattern += #"(?:@"(?<"# + keyVariableCaptureName + #">(?!ic_)[_a-z0-9]*[_][a-z0-9]+)")*(?:@"(?<"# + anyStringVariableCaptureName + #">\S*)")*"#

var allSwiftStringPattern = ""
settings.swiftExceptions.forEach { exception in
    allSwiftStringPattern += #"(?<!("# + exception + #"))"#
}

allSwiftStringPattern += #"(?:"(?<"# + keyVariableCaptureName + #">(?!ic_)[_a-z0-9]*[_][a-z0-9]+)")*(?:"(?<"# + anyStringVariableCaptureName + #">\S*)")*"#
let langRegExp = #"\/(?<"# + keyVariableCaptureName + #">\S+)[.]lproj\/"#

if settings.shouldAnalyzeSwift {
    processSwiftFiles(swiftFilePathSet: swiftFilePathSet,
                      swiftKeys: &swiftKeys,
                      allSwiftStrings: &allSwiftStrings,
                      allProbablyKeys: &allProbablyKeys)

}

if settings.shouldAnalyzeObjC {
    let objCFilePathSet = mFilePathSet.union(hFilePathSet)

    processObjCFiles(objCFilePathSet: objCFilePathSet,
                     objCKeys: &objCKeys,
                     allSwiftStrings: &allSwiftStrings,
                     allProbablyKeys: &allProbablyKeys)
}

var availableKeys = [String: Set<String>]()

processLocalizableFiles(localizableFilePathDict: localizableFilePathDict, localizationsDict: &localizationsDict, availableKeys: &availableKeys)
processLocalizableDictFiles(localizableDictFilePathDict: localizableDictFilePathDict, availableKeys: &availableKeys)

// GET RESULTS
let combinedUsedLocalizedKeys = swiftKeys.union(objCKeys)
var untranslatedKeys = [String: Set<String>]()

availableKeys.keys.forEach { (key: String) in
    var usedKeys = combinedUsedLocalizedKeys
    usedKeys.subtract(availableKeys[key]!)
    untranslatedKeys[key] = usedKeys
}

var unusedLocalizationsDict = [String: [Section]]()

localizationsDict.keys.forEach { key in
    localizationsDict[key]?.forEach { (section: Section) in
        var unusedSection = Section(name: section.name, translations: [TranslationPair]())
        section.translations.forEach { pair in
            if !combinedUsedLocalizedKeys.contains(pair.key) {
                unusedSection.translations.append(pair)
            }
        }
        if unusedSection.translations.count > 0 {
            if unusedLocalizationsDict[key] != nil {
                unusedLocalizationsDict[key]?.append(unusedSection)
            } else {
                unusedLocalizationsDict[key] = [unusedSection]
            }
        }
    }
}

// SAVE FILES

let endTime = Date()
let consumedTime = endTime.timeIntervalSinceReferenceDate - startTime.timeIntervalSinceReferenceDate
print("consumed time: ", Int(consumedTime), "sec")

//dump(unusedLocalizationsDict)

/*

// [lang: Set<key>]
let langKeysDict = localizationsDict.mapValues { Set($0.keys) }
let langTranslationsDict = localizationsDict.mapValues { Set($0.values) }

let langKeysSubtractUsedKeysDict = langKeysDict.mapValues { $0.subtracting(combinedUsedLocalizedKeys) }
// subtract all used strings because sometimes they used as just strings without localized construction
let extraTranslations = langKeysSubtractUsedKeysDict.mapValues { $0.subtracting(allSwiftStrings) }

if settings.translationDuplication {
    let duplicatedTranslations = localizationsDict.mapValues { (oneLangDict: [String: String]) -> [String: [String]] in
        //  translation: keys
        var translationKeysDict = [String: [String]]()

        oneLangDict.forEach { (arg: (key: String, value: String)) in
            let (key, value) = arg
            if translationKeysDict[value] != nil {
                translationKeysDict[value]!.append(key)
            } else {
                translationKeysDict[value] = [key]
            }
        }

        return translationKeysDict.filter { _, value in value.count > 1 }
    }

    print("duplicatedTranslations")
    dump(duplicatedTranslations)
}

print("\n\n")
print("extraTranslations")
//print(extraTranslations)
dump(extraTranslations)

// print("allSwiftStrings")
// dump(allSwiftStrings)

// print("allProbablyKeys")
// dump(allProbablyKeys)

print("keys without translation")
let keysWithoutTranslation = langKeysDict.mapValues { combinedUsedLocalizedKeys.subtracting($0) }

print(keysWithoutTranslation)

print("probably keys without translation")
let probablyKeysWithoutTranslation = langKeysDict.mapValues { allProbablyKeys.subtracting($0).subtracting(combinedUsedLocalizedKeys.subtracting($0)) }

print(probablyKeysWithoutTranslation)
*/

// FUNCTIONS

func readPlist() -> Settings {

    //    let path = FileManager.default.currentDirectoryPath + "/LocalizedStringsTool.plist"
    let path = "/Users/andrewmbp-office/Library/Developer/Xcode/DerivedData/LocalizedStringsTool-blwtdzgdconutmbtojnabaztzxrf/Build/Products/Debug/LocalizedStringsTool.plist"

    do {
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)
        return try PropertyListDecoder().decode(Settings.self, from: data)

    } catch {
        NSLog(error.localizedDescription)
        NSLog("Default settings will be used")

        return Settings(
            projectRootFolderPath: FileManager.default.currentDirectoryPath,
            unusedTranslations: true,
            translationDuplication: true,
            untranslatedKeys: true,
            allUntranslatedStrings: false,
            differentKeysInTranslations: false,
            shouldAnalyzeSwift: true,
            shouldAnalyzeObjC: true,
            customObjCPatternPrefixes: [#"NSLocalizedString("#],
            objCExceptions: [],
            swiftExceptions: [],
            folderExcludedNames: ["Pods"]
        )
    }
}

func increaseProgress() {
    currentFilesCountHandled += 1

    let maxLength = 50
    var currentLength = (maxLength * currentFilesCountHandled) / commonFilesCount

    currentLength = max(0, currentLength)
    var progressString = ""
    for _ in 0 ..< currentLength {
        progressString += "■"
    }
    for _ in 0 ..< maxLength - currentLength {
        progressString += "□"
    }
    let resultString = String(format: "\u{1B}[1A\u{1B} %@ ", progressString)
//    print(resultString)
}

func getAllFilesPaths(
    swiftFilePathSet: inout Set<String>,
    hFilePathSet: inout  Set<String>,
    mFilePathSet: inout Set<String>,
    localizableFilePathDict: inout [String],
    localizableDictFilePathDict: inout [String]) {
    let manager = FileManager.default
    let enumerator = manager.enumerator(atPath: settings.projectRootFolderPath)

    while let element = enumerator?.nextObject() as? String {
        var shouldHandlePath = true
        for pathElement in settings.folderExcludedNames {
            if element.contains(pathElement) {
                shouldHandlePath = false
            }
        }

        if shouldHandlePath {
            if element.hasSuffix(".swift") && settings.shouldAnalyzeSwift {
                swiftFilePathSet.insert(element)
            } else if element.hasSuffix(".h") && settings.shouldAnalyzeObjC {
                hFilePathSet.insert(element)
            } else if element.hasSuffix(".m") && settings.shouldAnalyzeObjC {
                mFilePathSet.insert(element)
            } else if element.hasSuffix("Localizable.strings") {
                localizableFilePathDict.append(element)
            } else if element.hasSuffix("Localizable.stringsdict") {
                localizableDictFilePathDict.append(element)
            }
        }
        commonFilesCount = swiftFilePathSet.count + hFilePathSet.count + mFilePathSet.count + localizableFilePathDict.count + localizableDictFilePathDict.count
    }
}

func matchingStrings(regex: String, text: String, names: [String] = [keyVariableCaptureName]) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: regex, options: []) else { return [] }

    let nsText = text as NSString
    let results = regex.matches(in: text, options: [], range: NSMakeRange(0, text.count))

    return results
        .map { result -> [String] in
        names
            .map { (name: String) -> String? in
                result.range(withName: name).location != NSNotFound
                ? nsText.substring(with: result.range(withName: name))
                : nil
            }
            .compactMap { $0 }
    }
}

func processSwiftFiles(swiftFilePathSet: Set<String>,
                       swiftKeys: inout Set<String>,
                       allSwiftStrings: inout Set<String>,
                       allProbablyKeys: inout Set<String>) {
    swiftFilePathSet.forEach { swiftFilePath in
        autoreleasepool {
            if let fileText = try? String(contentsOf: URL(fileURLWithPath: settings.projectRootFolderPath + "/" + swiftFilePath), encoding: .utf8) {
                matchingStrings(regex: swiftKeyPattern, text: fileText)
                    .map { $0.first }
                    .compactMap { $0 }
                    .forEach { swiftKeys.insert($0) }

                matchingStrings(regex: swiftOldKeyPattern, text: fileText)
                    .map { $0.first }
                    .compactMap { $0 }
                    .forEach { swiftKeys.insert($0) }

                if settings.allUntranslatedStrings {
                    matchingStrings(regex: allSwiftStringPattern, text: fileText, names: [anyStringVariableCaptureName])
                        .map { $0.first }
                        .compactMap { $0 }
                        .forEach { allSwiftStrings.insert($0) }
                }
                matchingStrings(regex: allSwiftStringPattern, text: fileText)
                    .map { $0.first }
                    .compactMap { $0 }
                    .forEach { allProbablyKeys.insert($0) }
            }
        }
        increaseProgress()
    }
}

func processObjCFiles(objCFilePathSet: Set<String>,
                      objCKeys: inout Set<String>,
                      allSwiftStrings: inout Set<String>,
                      allProbablyKeys: inout Set<String>) {

    objCFilePathSet.forEach { filePath in
        autoreleasepool {
            if let fileText = try? String(contentsOf: URL(fileURLWithPath: settings.projectRootFolderPath + "/" + filePath), encoding: .utf8) {
                matchingStrings(regex: objCKeyPattern, text: fileText)
                    .map { $0.first }
                    .compactMap { $0 }
                    .forEach { objCKeys.insert($0) }
                if settings.allUntranslatedStrings {
                    matchingStrings(regex: allObjCStringPattern, text: fileText, names: [anyStringVariableCaptureName])
                        .map { $0.first }
                        .compactMap { $0 }
                        .forEach { allSwiftStrings.insert($0) }
                }
                matchingStrings(regex: allObjCStringPattern, text: fileText)
                    .map { $0.first }
                    .compactMap { $0 }
                    .forEach { allProbablyKeys.insert($0) }
            }
        }
        increaseProgress()
    }
}

func processLocalizableFiles(localizableFilePathDict: [String],
                             localizationsDict: inout [String: [Section]],
                             availableKeys: inout [String: Set<String>]) {
    localizableFilePathDict.forEach { dirPath in
        autoreleasepool {
            let path = (settings.projectRootFolderPath + "/" + dirPath)
            do {
                var oneLangAvailableKeys = Set<String>()
                // Koto utf8, Mono utf16
                let fileText8 = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
                let fileText16 = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf16)
                let arr = [fileText8, fileText16].compactMap { $0 }

                if let fileText = arr.first {
                    let searchResults: [[String]] = matchingStrings(
                        regex: localizedSectionPattern,
                        text: fileText,
                        names: [translationSectionVariableCaptureName, keyVariableCaptureName, translationVariableCaptureName]
                    )
                    var sections = [Section]()

                    for result: [String] in searchResults {
                        // found new section
                        if result.count == 3 {
                            sections.append(Section(name: result[0], translations: [TranslationPair(key: result[1], translation: result[2])]))
                            oneLangAvailableKeys.insert(result[1])

                            // add to previous section
                        } else if result.count == 2 {
                            oneLangAvailableKeys.insert(result[0])
                            if sections.count > 0 {
                                sections[sections.count - 1].translations.append(TranslationPair(key: result[0], translation: result[1]))
                            } else {
                                sections.append(Section(name: "", translations: [TranslationPair(key: result[0], translation: result[1])]))
                            }
                        }
                    }
                    let name = langName(for: dirPath)
                    localizationsDict[name] = sections
                    availableKeys[name] = oneLangAvailableKeys
                }
            }
        }
        increaseProgress()
    }
}

func processLocalizableDictFiles(localizableDictFilePathDict: [String], availableKeys: inout [String: Set<String>]) {

    localizableDictFilePathDict.forEach { dirPath in
        let path = (settings.projectRootFolderPath + "/" + dirPath)
        let fileURL = URL(fileURLWithPath: path)
        autoreleasepool {
            if let dict = NSDictionary(contentsOf: fileURL) as? Dictionary<String, AnyObject> {
                let name = langName(for: dirPath)
                availableKeys[name] = availableKeys[name]?.union(Set(dict.keys))
            }
        }
        increaseProgress()
    }
}

func langName(for filePath: String) -> String {
    matchingStrings(regex: langRegExp, text: filePath).first?.first ?? ""
}
