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

// TestArchitectureDocNamesEveryFileAndStage fails when a non-test Go file in
// this package (or main.go), or a process* method on Converter, is missing
// from docs/architecture.md. A new file or pipeline step forces a line in the
// doc. It checks that names appear, not that what the doc says about them is
// right.
func TestArchitectureDocNamesEveryFileAndStage(t *testing.T) {
	doc := readArchitectureDoc(t)

	files, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"main.go"}
	for _, f := range files {
		if !strings.HasSuffix(f, "_test.go") {
			want = append(want, filepath.Base(f))
		}
	}
	for _, name := range want {
		if !strings.Contains(doc, name) {
			t.Errorf("%s does not mention %s; add it to the files table", architectureDocPath, name)
		}
	}

	for _, method := range converterProcessMethods(t) {
		if !strings.Contains(doc, method) {
			t.Errorf("%s does not mention %s; add it to the steps table", architectureDocPath, method)
		}
	}
}

// TestInvariantsCiteRealTests fails when docs/architecture.md names a test
// function that no longer exists in this package. The rules table cites the
// test that pins each rule; a renamed or deleted test must update the doc.
func TestInvariantsCiteRealTests(t *testing.T) {
	doc := readArchitectureDoc(t)

	defined := map[string]bool{}
	testFiles, err := filepath.Glob("*_test.go")
	if err != nil {
		t.Fatal(err)
	}
	funcDecl := regexp.MustCompile(`(?m)^func (Test\w+)\(`)
	for _, f := range testFiles {
		src, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		for _, m := range funcDecl.FindAllStringSubmatch(string(src), -1) {
			defined[m[1]] = true
		}
	}

	cited := regexp.MustCompile("`(Test\\w+)`").FindAllStringSubmatch(doc, -1)
	if len(cited) == 0 {
		t.Fatalf("%s cites no test functions; the rules table should name one per rule", architectureDocPath)
	}
	for _, m := range cited {
		if !defined[m[1]] {
			t.Errorf("%s cites %s, which is not defined in buildconfig/*_test.go", architectureDocPath, m[1])
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

// converterProcessMethods returns the names of every method on *Converter
// whose name starts with "process", in declaration order across the
// package's non-test files.
func converterProcessMethods(t *testing.T) []string {
	t.Helper()
	fset := token.NewFileSet()
	pkgs, err := parser.ParseDir(fset, ".", func(fi os.FileInfo) bool {
		return !strings.HasSuffix(fi.Name(), "_test.go")
	}, 0)
	if err != nil {
		t.Fatal(err)
	}
	var methods []string
	for _, pkg := range pkgs {
		for _, file := range pkg.Files {
			for _, decl := range file.Decls {
				fn, ok := decl.(*ast.FuncDecl)
				if !ok || fn.Recv == nil || len(fn.Recv.List) == 0 {
					continue
				}
				star, ok := fn.Recv.List[0].Type.(*ast.StarExpr)
				if !ok {
					continue
				}
				if ident, ok := star.X.(*ast.Ident); !ok || ident.Name != "Converter" {
					continue
				}
				if strings.HasPrefix(fn.Name.Name, "process") {
					methods = append(methods, fn.Name.Name)
				}
			}
		}
	}
	if len(methods) == 0 {
		t.Fatal("found no process* methods on Converter")
	}
	return methods
}
