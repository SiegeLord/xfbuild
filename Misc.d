module xfbuild.Misc;

private {
	import tango.text.Util;
	import tango.text.convert.Format;
}



bool startsWith(char[] foo, char[] prefix) {
	return foo.length >= prefix.length && foo[0..prefix.length] == prefix;
}


char[][] decomposeString(char[] str, char[][] foo ...) {
	char[][] res;
	
	foreach (fi, f; foo) {
		if (f is null) {
			if (fi == foo.length -1) {
				res ~= str;
				str = null;
				break;
			} else {
				auto delim = foo[fi+1];
				assert (delim !is null);
				int l = str.locatePattern(delim);
				if (l == str.length) {
					return null;		// fail
				}
				res ~= str[0..l];
				str = str[l..$];
			}
		} else if (" " == f) {
			if (str.length > 0 && isSpace(str[0])) {
				str = triml(str);
			} else {
				return null;
			}
		} else {
			if (str.startsWith(f)) {
				str = str[f.length..$];
			} else {
				return null;		// fail
			}
		}
	}
	
	return str.length > 0 ? null : res;
}


unittest {
	void test(char[][] res, char[] str, char[][] decompose ...) {
		assert (res == str.decomposeString(decompose), Format("Failed on: {}: got {} instead of {}", str, str.decomposeString(decompose), res));
	}
	test(["Foo.bar.Baz"], `Import::semantic(Foo.bar.Baz)`, `Import::semantic(`, null, `)`);
	test(["Foo.bar.Baz", "lol/wut"], `Import::semantic('Foo.bar.Baz', 'lol/wut')`, `Import::semantic('`, null, `', '`, null, `')`);
	test(["lolwut"], `semantic   	lolwut`, "semantic", " ", null);
	test([`defend\terrain\Generator.obj`, "Generator"], `defend\terrain\Generator.obj(Generator)`, cast(char[])null, "(", null, ")");
	test([`.objs\ddl-DDLException.obj`, `ddl-DDLException`], `.objs\ddl-DDLException.obj(ddl-DDLException)`, cast(char[])null, `(`, null, `)`);
}
