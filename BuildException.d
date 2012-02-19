module xfbuild.BuildException;


class BuildException : Exception {
    this(immutable(char)[] msg) {
        super(msg);
    }
    this(immutable(char)[]m,immutable(char)[]fl,long ln,Exception next=null){
        super(m,fl,ln,next);
    }
}
