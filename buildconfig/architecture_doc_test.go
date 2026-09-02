package buildconfig

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

const architectureDocPath = "../docs/architecture.md"

// docSymbols are the functions and types docs/architecture.md relies on
// beyond the process* methods on Converter, which are found by parsing the
// package. Each must stay declared here and named on the page; a rename
// fails the test until the page and this list follow.
var docSymbols = []string{
	"Run", "Metadata", "ParseOptionalFields", "PluginOptionalFields",
	"Convert", "Converter", "uniqueName", "sanitizeDNS1123Label", "filterMetadata",
	"warnf", "recordWarning", "boundedWarnings", "truncateReason",
	"getPullSecret", "generateServiceAccount", "addRegistries",
	"toUnstructured", "stripSerializationNoise",
}

var (
	backtickedToken = regexp.MustCompile("`([^`\n]+)`")
	citedTestFunc   = regexp.MustCompile("`(Test\\w+)`")
	citedTestFile   = regexp.MustCompile("`(\\w+_test\\.go)`")
	testFuncDecl    = regexp.MustCompile(`(?m)^func (Test\w+)\(`)
)

// TestArchitectureDocNamesEveryFileAndStage fails when a non-test Go file in
// this package (or main.go), or a process* method on Converter, is not named
// in docs/architecture.md as an exact backticked token. A new file or
// pipeline step forces a line in the doc. It checks that names appear, not
// that what the doc says about them is right.
func TestArchitectureDocNamesEveryFileAndStage(t *testing.T) {
	tokens := backtickedTokens(readArchitectureDoc(t))

	if !tokens["main.go"] {
		t.Errorf("%s does not name main.go; add it to the files table", architectureDocPath)
	}
	files, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatalf("glob *.go: %v", err)
	}
	for _, f := range files {
		if strings.HasSuffix(f, "_test.go") {
			continue
		}
		name := filepath.Base(f)
		if !tokens[name] && !tokens["buildconfig/"+name] {
			t.Errorf("%s does not name %s; add it to the files table", architectureDocPath, name)
		}
	}

	for _, method := range packageDeclarations(t).processMethods {
		if !tokens[method] {
			t.Errorf("%s does not name %s; add it to the steps table", architectureDocPath, method)
		}
	}
}

// TestArchitectureDocSymbolsExist fails when a function or type in docSymbols
// is no longer declared in this package, or is no longer named in
// docs/architecture.md. It catches the renames the process* check cannot.
func TestArchitectureDocSymbolsExist(t *testing.T) {
	tokens := backtickedTokens(readArchitectureDoc(t))
	declared := packageDeclarations(t).names

	for _, sym := range docSymbols {
		if !declared[sym] {
			t.Errorf("%s relies on %s, which is not declared in this package; update the page and docSymbols", architectureDocPath, sym)
		}
		if !tokens[sym] {
			t.Errorf("%s no longer names %s; add it back or drop it from docSymbols", architectureDocPath, sym)
		}
	}
}

// TestInvariantsCiteRealTests fails when docs/architecture.md cites a test
// function that is not defined in this package, when a row of the rules
// table cites a test file that does not exist, or when a row cites nothing
// without saying it is convention.
func TestInvariantsCiteRealTests(t *testing.T) {
	doc := readArchitectureDoc(t)
	defined := definedTestFuncs(t)

	for _, m := range citedTestFunc.FindAllStringSubmatch(doc, -1) {
		if !defined[m[1]] {
			t.Errorf("%s cites %s, which is not defined in buildconfig/*_test.go", architectureDocPath, m[1])
		}
	}

	for _, row := range rulesTableRows(t, doc) {
		pinnedBy := row.cells[len(row.cells)-1]
		funcs := citedTestFunc.FindAllStringSubmatch(pinnedBy, -1)
		files := citedTestFile.FindAllStringSubmatch(pinnedBy, -1)
		for _, f := range files {
			if _, err := os.Stat(f[1]); err != nil {
				t.Errorf("rule %s cites %s, which does not exist in buildconfig/", row.number, f[1])
			}
		}
		if len(funcs) == 0 && len(files) == 0 && !strings.Contains(pinnedBy, "convention") {
			t.Errorf("rule %s cites no test and does not say it is convention: %q", row.number, pinnedBy)
		}
	}
}

func readArchitectureDoc(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(architectureDocPath)
	if err != nil {
		t.Fatalf("read %s: %v", architectureDocPath, err)
	}
	return string(b)
}

// backtickedTokens returns every backtick-quoted string in doc as a set, so
// callers match whole tokens rather than substrings.
func backtickedTokens(doc string) map[string]bool {
	tokens := map[string]bool{}
	for _, m := range backtickedToken.FindAllStringSubmatch(doc, -1) {
		tokens[m[1]] = true
	}
	return tokens
}

type declarations struct {
	// names holds every top-level function, method, type, constant and
	// variable declared in the package's non-test files.
	names map[string]bool
	// processMethods holds the process* methods on *Converter, in
	// declaration order.
	processMethods []string
}

func packageDeclarations(t *testing.T) declarations {
	t.Helper()
	fset := token.NewFileSet()
	pkgs, err := parser.ParseDir(fset, ".", func(fi os.FileInfo) bool {
		return !strings.HasSuffix(fi.Name(), "_test.go")
	}, 0)
	if err != nil {
		t.Fatalf("parse package: %v", err)
	}
	d := declarations{names: map[string]bool{}}
	for _, pkg := range pkgs {
		for _, file := range pkg.Files {
			for _, decl := range file.Decls {
				switch decl := decl.(type) {
				case *ast.FuncDecl:
					d.names[decl.Name.Name] = true
					if isConverterMethod(decl) && strings.HasPrefix(decl.Name.Name, "process") {
						d.processMethods = append(d.processMethods, decl.Name.Name)
					}
				case *ast.GenDecl:
					for _, spec := range decl.Specs {
						switch spec := spec.(type) {
						case *ast.TypeSpec:
							d.names[spec.Name.Name] = true
						case *ast.ValueSpec:
							for _, name := range spec.Names {
								d.names[name.Name] = true
							}
						}
					}
				}
			}
		}
	}
	if len(d.processMethods) == 0 {
		t.Fatal("found no process* methods on Converter")
	}
	return d
}

func isConverterMethod(fn *ast.FuncDecl) bool {
	if fn.Recv == nil || len(fn.Recv.List) == 0 {
		return false
	}
	star, ok := fn.Recv.List[0].Type.(*ast.StarExpr)
	if !ok {
		return false
	}
	ident, ok := star.X.(*ast.Ident)
	return ok && ident.Name == "Converter"
}

// definedTestFuncs returns the names of every Test function declared in the
// package's test files.
func definedTestFuncs(t *testing.T) map[string]bool {
	t.Helper()
	defined := map[string]bool{}
	testFiles, err := filepath.Glob("*_test.go")
	if err != nil {
		t.Fatalf("glob *_test.go: %v", err)
	}
	for _, f := range testFiles {
		src, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("read %s: %v", f, err)
		}
		for _, m := range testFuncDecl.FindAllStringSubmatch(string(src), -1) {
			defined[m[1]] = true
		}
	}
	return defined
}

type ruleRow struct {
	number string
	cells  []string
}

// rulesTableRows returns the numbered rows of the "Rules that must stay true"
// table, each split into its trimmed cells.
func rulesTableRows(t *testing.T, doc string) []ruleRow {
	t.Helper()
	const heading = "## Rules that must stay true"
	start := strings.Index(doc, heading)
	if start < 0 {
		t.Fatalf("%s has no %q section", architectureDocPath, heading)
	}
	section := doc[start+len(heading):]
	if end := strings.Index(section, "\n## "); end >= 0 {
		section = section[:end]
	}

	var rows []ruleRow
	for _, line := range strings.Split(section, "\n") {
		if !strings.HasPrefix(line, "|") {
			continue
		}
		cells := strings.Split(strings.Trim(line, "|"), "|")
		for i := range cells {
			cells[i] = strings.TrimSpace(cells[i])
		}
		if len(cells) < 2 || strings.Trim(cells[0], "0123456789") != "" {
			continue
		}
		rows = append(rows, ruleRow{number: cells[0], cells: cells})
	}
	if len(rows) == 0 {
		t.Fatalf("%s has no numbered rows in the rules table", architectureDocPath)
	}
	return rows
}
