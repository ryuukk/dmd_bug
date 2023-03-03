module object;
pragma(msg, "-- using custom runtime --");

version(WASM)
{
    alias size_t = uint;
    alias ptrdiff_t = int;
}
else
{
    alias size_t = typeof(int.sizeof);
    alias ptrdiff_t = typeof(cast(void*)0 - cast(void*)0);
}

alias noreturn = typeof(*null);

alias string  = immutable(char)[];
alias wstring = immutable(wchar)[];
alias dstring = immutable(dchar)[];

alias u8 = ubyte;
alias u16 = ushort;
alias u32 = uint;
alias u64 = ulong;

alias i8 = byte;
alias i16 = short;
alias i32 = int;
alias i64 = long;

alias f32 = float;
alias f64 = double;

alias size = ptrdiff_t;
alias usize = size_t;

version (WASM)
{
    /+
        mem must be 0 (it is index of memory thing)
        delta is in 64 KB pages
        return OLD size in 64 KB pages, or size_t.max if it failed.
    +/
    pragma(LDC_intrinsic, "llvm.wasm.memory.grow.i32")
    extern(C) int llvm_wasm_memory_grow(int mem, int delta);


    // in 64 KB pages
    pragma(LDC_intrinsic, "llvm.wasm.memory.size.i32")
    extern(C) int llvm_wasm_memory_size(int mem);

    extern(C) void main();
    export extern(C) void _start() {main(); }
}

extern(C) int _Dmain(string[] args);

version(LDC)
{
    // ldc complains with -betterC
    extern(C) void _d_array_slice_copy(void* dst, size_t dstlen, void* src, size_t srclen, size_t elemsz)
    {
        import ldc.intrinsics: llvm_memcpy;
        llvm_memcpy!size_t(dst, src, dstlen * elemsz, 0);
    }
}

// The compiler lowers `lhs == rhs` to `__equals(lhs, rhs)` for
// * dynamic arrays,
// * (most) arrays of different (unqualified) element types, and
// * arrays of structs with custom opEquals.

 // The scalar-only overload takes advantage of known properties of scalars to
 // reduce template instantiation. This is expected to be the most common case.
bool __equals(T1, T2)(scope const T1[] lhs, scope const T2[] rhs)
@nogc nothrow pure @trusted
if (__traits(isScalar, T1) && __traits(isScalar, T2))
{
    const length = lhs.length;

    static if (T1.sizeof == T2.sizeof
        // Signedness needs to match for types that promote to int.
        // (Actually it would be okay to memcmp bool[] and byte[] but that is
        // probably too uncommon to be worth checking for.)
        && (T1.sizeof >= 4 || __traits(isUnsigned, T1) == __traits(isUnsigned, T2))
        && !__traits(isFloating, T1) && !__traits(isFloating, T2))
    {
        if (__ctfe)
            return length == rhs.length && isEqual(lhs.ptr, rhs.ptr, length);
        else
        {
            // This would improperly allow equality of integers and pointers
            // but the CTFE branch will stop this function from compiling then.
            return length == rhs.length &&
                (!length || 0 == memcmp(cast(const void*) lhs.ptr, cast(const void*) rhs.ptr, length * T1.sizeof));
        }
    }
    else
    {
        return length == rhs.length && isEqual(lhs.ptr, rhs.ptr, length);
    }
}

bool __equals(T1, T2)(scope T1[] lhs, scope T2[] rhs)
if (!__traits(isScalar, T1) || !__traits(isScalar, T2))
{
    if (lhs.length != rhs.length)
        return false;

    if (lhs.length == 0)
        return true;

    static if (useMemcmp!(T1, T2))
    {
        if (!__ctfe)
        {
            static bool trustedMemcmp(scope T1[] lhs, scope T2[] rhs) @trusted @nogc nothrow pure
            {
                pragma(inline, true);
                return memcmp(cast(void*) lhs.ptr, cast(void*) rhs.ptr, lhs.length * T1.sizeof) == 0;
            }
            return trustedMemcmp(lhs, rhs);
        }
        else
        {
            foreach (const i; 0 .. lhs.length)
            {
                if (at(lhs, i) != at(rhs, i))
                    return false;
            }
            return true;
        }
    }
    else
    {
        foreach (const i; 0 .. lhs.length)
        {
            if (at(lhs, i) != at(rhs, i))
                return false;
        }
        return true;
    }
}

private
bool isEqual(T1, T2)(scope const T1* t1, scope const T2* t2, size_t length)
{
    foreach (const i; 0 .. length)
        if (t1[i] != t2[i])
            return false;
    return true;
}


pragma(inline, true)
private 
ref at(T)(T[] r, size_t i) @trusted
    // exclude opaque structs due to https://issues.dlang.org/show_bug.cgi?id=20959
    if (!(is(T == struct) && !is(typeof(T.sizeof))))
{
    static if (is(immutable T == immutable void))
        return (cast(ubyte*) r.ptr)[i];
    else
        return r.ptr[i];
}

private template BaseType(T)
{
    static if (__traits(isStaticArray, T))
        alias BaseType = BaseType!(typeof(T.init[0]));
    else static if (is(immutable T == immutable void))
        alias BaseType = ubyte;
    else static if (is(T == E*, E))
        alias BaseType = size_t;
    else
        alias BaseType = T;
}

private template useMemcmp(T1, T2)
{
    static if (T1.sizeof != T2.sizeof)
        enum useMemcmp = false;
    else
    {
        alias B1 = BaseType!T1;
        alias B2 = BaseType!T2;
        enum useMemcmp = __traits(isIntegral, B1) && __traits(isIntegral, B2)
           && !( (B1.sizeof < 4 || B2.sizeof < 4) && __traits(isUnsigned, B1) != __traits(isUnsigned, B2) );
    }
}

TTo[] __ArrayCast(TFrom, TTo)(return scope TFrom[] from)
{
   const fromSize = from.length * TFrom.sizeof;
   const toLength = fromSize / TTo.sizeof;

   if ((fromSize % TTo.sizeof) != 0)
   {
        //onArrayCastError(TFrom.stringof, fromSize, TTo.stringof, toLength * TTo.sizeof);
        assert(0);
   }

   struct Array
   {
       size_t length;
       void* ptr;
   }
   auto a = cast(Array*)&from;
   a.length = toLength; // jam new length
   return *cast(TTo[]*)a;
}

// switch
extern(C) void __switch_error()(string file = __FILE__, size_t line = __LINE__)
{
    LERRO("{} {}", file, line);
    //__switch_errorT(file, line);    
    assert(0, "No appropriate switch clause found");
}

/**
Support for switch statements switching on strings.
Params:
    caseLabels = sorted array of strings generated by compiler. Note the
        strings are sorted by length first, and then lexicographically.
    condition = string to look up in table
Returns:
    index of match in caseLabels, a negative integer if not found
*/
int __switch(T, caseLabels...)(/*in*/ const scope T[] condition) pure nothrow @safe @nogc
{
    // This closes recursion for other cases.
    static if (caseLabels.length == 0)
    {
        return int.min;
    }
    else static if (caseLabels.length == 1)
    {
        return __cmp(condition, caseLabels[0]) == 0 ? 0 : int.min;
    }
    // To be adjusted after measurements
    // Compile-time inlined binary search.
    else static if (caseLabels.length < 7)
    {
        int r = void;
        enum mid = cast(int)caseLabels.length / 2;
        if (condition.length == caseLabels[mid].length)
        {
            r = __cmp(condition, caseLabels[mid]);
            if (r == 0) return mid;
        }
        else
        {
            // Equivalent to (but faster than) condition.length > caseLabels[$ / 2].length ? 1 : -1
            r = ((condition.length > caseLabels[mid].length) << 1) - 1;
        }

        if (r < 0)
        {
            // Search the left side
            return __switch!(T, caseLabels[0 .. mid])(condition);
        }
        else
        {
            // Search the right side
            return __switch!(T, caseLabels[mid + 1 .. $])(condition) + mid + 1;
        }
    }
    else
    {
        // Need immutable array to be accessible in pure code, but case labels are
        // currently coerced to the switch condition type (e.g. const(char)[]).
        pure @trusted nothrow @nogc asImmutable(scope const(T[])[] items)
        {
            assert(__ctfe); // only @safe for CTFE
            immutable T[][caseLabels.length] result = cast(immutable)(items[]);
            return result;
        }
        static immutable T[][caseLabels.length] cases = asImmutable([caseLabels]);

        // Run-time binary search in a static array of labels.
        return __switchSearch!T(cases[], condition);
    }
}

extern(C) int __cmp(T)(scope const T[] lhs, scope const T[] rhs) @trusted pure @nogc nothrow
    if (__traits(isScalar, T))
{
    // Compute U as the implementation type for T
    static if (is(T == ubyte) || is(T == void) || is(T == bool))
        alias U = char;
    else static if (is(T == wchar))
        alias U = ushort;
    else static if (is(T == dchar))
        alias U = uint;
    else static if (is(T == ifloat))
        alias U = float;
    else static if (is(T == idouble))
        alias U = double;
    else static if (is(T == ireal))
        alias U = real;
    else
        alias U = T;

    static if (is(U == char))
    {
        return dstrcmp(cast(char[]) lhs, cast(char[]) rhs);
    }
    else static if (!is(U == T))
    {
        // Reuse another implementation
        return __cmp(cast(U[]) lhs, cast(U[]) rhs);
    }
    else
    {
        version (BigEndian)
        static if (__traits(isUnsigned, T) ? !is(T == __vector) : is(T : P*, P))
        {
            if (!__ctfe)
            {
                int c = memcmp(lhs.ptr, rhs.ptr, (lhs.length <= rhs.length ? lhs.length : rhs.length) * T.sizeof);
                if (c)
                    return c;
                static if (size_t.sizeof <= uint.sizeof && T.sizeof >= 2)
                    return cast(int) lhs.length - cast(int) rhs.length;
                else
                    return int(lhs.length > rhs.length) - int(lhs.length < rhs.length);
            }
        }

        immutable len = lhs.length <= rhs.length ? lhs.length : rhs.length;
        foreach (const u; 0 .. len)
        {
            auto a = lhs.ptr[u], b = rhs.ptr[u];
            static if (is(T : creal))
            {
                // Use rt.cmath2._Ccmp instead ?
                // Also: if NaN is present, numbers will appear equal.
                auto r = (a.re > b.re) - (a.re < b.re);
                if (!r) r = (a.im > b.im) - (a.im < b.im);
            }
            else
            {
                // This pattern for three-way comparison is better than conditional operators
                // See e.g. https://godbolt.org/z/3j4vh1
                const r = (a > b) - (a < b);
            }
            if (r) return r;
        }
        return (lhs.length > rhs.length) - (lhs.length < rhs.length);
    }
}


// This function is called by the compiler when dealing with array
// comparisons in the semantic analysis phase of CmpExp. The ordering
// comparison is lowered to a call to this template.
int __cmp(T1, T2)(T1[] s1, T2[] s2)
if (!__traits(isScalar, T1) && !__traits(isScalar, T2))
{
    alias U1 = Unqual!T1;
    alias U2 = Unqual!T2;

    static if (is(U1 == void) && is(U2 == void))
        static @trusted ref inout(ubyte) at(inout(void)[] r, size_t i) { return (cast(inout(ubyte)*) r.ptr)[i]; }
    else
        static @trusted ref R at(R)(R[] r, size_t i) { return r.ptr[i]; }

    // All unsigned byte-wide types = > dstrcmp
    immutable len = s1.length <= s2.length ? s1.length : s2.length;

    foreach (const u; 0 .. len)
    {
        static if (__traits(compiles, __cmp(at(s1, u), at(s2, u))))
        {
            auto c = __cmp(at(s1, u), at(s2, u));
            if (c != 0)
                return c;
        }
        else static if (__traits(compiles, at(s1, u).opCmp(at(s2, u))))
        {
            auto c = at(s1, u).opCmp(at(s2, u));
            if (c != 0)
                return c;
        }
        else static if (__traits(compiles, at(s1, u) < at(s2, u)))
        {
            if (int result = (at(s1, u) > at(s2, u)) - (at(s1, u) < at(s2, u)))
                return result;
        }
        else
        {
            // TODO: fix this legacy bad behavior, see
            // https://issues.dlang.org/show_bug.cgi?id=17244
            static assert(is(U1 == U2), "Internal error.");
            auto c = (() @trusted => memcmp(&at(s1, u), &at(s2, u), U1.sizeof))();
            if (c != 0)
                return c;
        }
    }
    return (s1.length > s2.length) - (s1.length < s2.length);
}

private template Unqual(T : const U, U)
{
    static if (is(U == shared V, V))
        alias Unqual = V;
    else
        alias Unqual = U;
}

// binary search in sorted string cases, also see `__switch`.
private int __switchSearch(T)(/*in*/ const scope T[][] cases, /*in*/ const scope T[] condition) pure nothrow @safe @nogc
{
    size_t low = 0;
    size_t high = cases.length;

    do
    {
        auto mid = (low + high) / 2;
        int r = void;
        if (condition.length == cases[mid].length)
        {
            r = __cmp(condition, cases[mid]);
            if (r == 0) return cast(int) mid;
        }
        else
        {
            // Generates better code than "expr ? 1 : -1" on dmd and gdc, same with ldc
            r = ((condition.length > cases[mid].length) << 1) - 1;
        }

        if (r > 0) low = mid + 1;
        else high = mid;
    }
    while (low < high);

    // Not found
    return -1;
}

// from spasm
void _d_array_init_i16(ushort* a, size_t n, ushort v)
{
    auto p = a;
    auto end = a + n;
    while (p !is end)
        *p++ = v;
}

void _d_array_init_i32(uint* a, size_t n, uint v)
{
    auto p = a;
    auto end = a + n;
    while (p !is end)
        *p++ = v;
}

void _d_array_init_i64(ulong* a, size_t n, ulong v)
{
    auto p = a;
    auto end = a + n;
    while (p !is end)
        *p++ = v;
}

void _d_array_init_float(float* a, size_t n, float v)
{
    auto p = a;
    auto end = a + n;
    while (p !is end)
        *p++ = v;
}

void _d_array_init_double(double* a, size_t n, double v)
{
    auto p = a;
    auto end = a + n;
    while (p !is end)
        *p++ = v;
}

void _d_array_init_real(real* a, size_t n, real v)
{
    auto p = a;
    auto end = a + n;
    while (p !is end)
        *p++ = v;
}

void _d_array_init_pointer(void** a, size_t n, void* v)
{
    auto p = a;
    auto end = a + n;
    while (p !is end)
        *p++ = v;
}

void _d_array_init_mem(void* a, size_t na, void* v, size_t nv)
{
    auto p = a;
    auto end = a + na * nv;
    while (p !is end)
    {
        version (LDC)
        {
            import ldc.intrinsics: llvm_memcpy;
            llvm_memcpy(p, v, nv, 0);
        }
        else
            memcpy(p, v, nv);
        p += nv;
    }
}

extern(C) bool _xopEquals(in void*, in void*)
{ 
    assert(0, "not implemented");
}

extern(C) bool _xopCmp(in void*, in void*) 
{
    assert(0, "not implemented");
    //return false;
}

extern(C) void _d_arraybounds_slice(string file, uint line, size_t lower, size_t upper, size_t length)
{
    assert(0, "not implemented");
}

extern(C) void _d_arraybounds_index(string file, uint line, size_t index, size_t length)
{
    assert(0, "not implemented");
}

extern(C) void _d_arraybounds(string file, size_t line) { //, size_t lwr, size_t upr, size_t length) {
    assert(0);
}

extern(C)short *_memset16(short *p, short value, size_t count)
{
    short *pstart = p;
    short *ptop;

    for (ptop = &p[count]; p < ptop; p++)
        *p = value;
    return pstart;
}

extern(C) int *_memset32(int *p, int value, size_t count)
{
    version (D_InlineAsm_X86)
    {
        asm
        {
            mov     EDI,p           ;
            mov     EAX,value       ;
            mov     ECX,count       ;
            mov     EDX,EDI         ;
            rep                     ;
            stosd                   ;
            mov     EAX,EDX         ;
        }
    }
    else
    {
        int *pstart = p;
        int *ptop;

        for (ptop = &p[count]; p < ptop; p++)
            *p = value;
        return pstart;
    }
}
extern(C) long *_memset64(long *p, long value, size_t count)
{
    long *pstart = p;
    long *ptop;

    for (ptop = &p[count]; p < ptop; p++)
        *p = value;
    return pstart;
}

extern(C) void[] *_memset128ii(void[] *p, void[] value, size_t count)
{
    void[] *pstart = p;
    void[] *ptop;

    for (ptop = &p[count]; p < ptop; p++)
        *p = value;
    return pstart;
}

extern(C) void *_memsetn(void *p, void *value, int count, size_t sizelem)
{   
    void *pstart = p;
    int i;

    for (i = 0; i < count; i++)
    {
        memcpy(p, value, sizelem);
        p = cast(void *)(cast(char *)p + sizelem);
    }
    return pstart;
}

extern(C) float *_memsetFloat(float *p, float value, size_t count)
{
    float *pstart = p;
    float *ptop;

    for (ptop = &p[count]; p < ptop; p++)
        *p = value;
    return pstart;
}

extern(C) double *_memsetDouble(double *p, double value, size_t count)
{
    double *pstart = p;
    double *ptop;

    for (ptop = &p[count]; p < ptop; p++)
        *p = value;
    return pstart;
}


package:
void *memcpy(void* dest, const(void)* src, size_t n) pure @nogc nothrow
{
	ubyte *d = cast(ubyte*) dest;
	const (ubyte) *s = cast(const(ubyte)*)src;
	for (; n; n--) *d++ = *s++;
	return dest;
}

int memcmp(const(void)* s1, const(void*) s2, size_t n) pure @nogc nothrow @trusted
{
	auto b = cast(ubyte*) s1;
	auto b2 = cast(ubyte*) s2;
	foreach(i; 0 .. n) {
		if(auto diff = *b -  *b2)
			return diff;
		b++;
		b2++;
	}
	return 0;
}


int dstrcmp()( scope const char[] s1, scope const char[] s2 ) @trusted
{
    immutable len = s1.length <= s2.length ? s1.length : s2.length;
    if (__ctfe)
    {
        foreach (const u; 0 .. len)
        {
            if (s1[u] != s2[u])
                return s1[u] > s2[u] ? 1 : -1;
        }
    }
    else
    {
        const ret = memcmp( s1.ptr, s2.ptr, len );
        if ( ret )
            return ret;
    }
    return (s1.length > s2.length) - (s1.length < s2.length);
}

