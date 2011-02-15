module xfbuild.BuildException;


class BuildException : Exception {
    this(char[] msg) {
        super(msg);
    }
    this(char[]m,char[]fl,long ln,Exception next=null){
        super(m,fl,ln,next);
    }
}
