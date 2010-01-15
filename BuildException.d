module xfbuild.BuildException;


class BuildException : Exception {
	this(char[] msg) {
		super(msg);
	}
}
