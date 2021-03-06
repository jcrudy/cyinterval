from datetime import date

cdef class BaseInterval:
    '''
    Interpreted as the conjunction of two inequalities.
    '''
    def __reduce__(BaseInterval self):
        return (self.__class__, self.init_args())
        
    def __hash__(BaseInterval self):
        return hash(self.__reduce__())
    
    def __nonzero__(BaseInterval self):
        return not self.empty()
    
    def __richcmp__(BaseInterval self, other, int op):
        if other.__class__ is not self.__class__:
            return NotImplemented
        return self.richcmp(other, op)
        
    def __and__(BaseInterval self, other):
        if other.__class__ is self.__class__:
            raise NotImplementedError('Only intervals of the same type can be intersected')
        return self.intersection(other)
    
    def __rand__(BaseInterval self, other):
        if self.__class__ is not other.__class__:
            return NotImplemented
        return other.__and__(other)
    
    def __contains__(BaseInterval self, item):
        return self.contains(item)
    
    def __str__(BaseInterval self):
        return (('[' if self.lower_closed else '(') + (str(self.lower_bound) if self.lower_bounded else '-infty') + ',' + 
                (str(self.upper_bound) if self.upper_bounded else 'infty') + (']' if self.upper_closed else ')'))
    
    def __repr__(BaseInterval self):
        return str(self)
        
cdef class BaseIntervalSet:
    def __str__(BaseIntervalSet self):
        return 'U'.join(map(str, self.intervals)) if self.intervals else '{}'
    
    def __contains__(BaseIntervalSet self, item):
        return self.contains(item)
    
    def __repr__(BaseIntervalSet self):
        return str(self)
    
    def __richcmp__(BaseIntervalSet self, other, int op):
        if self.__class__ is not other.__class__:
            return NotImplemented
        return self.richcmp(other, op)
    
    def __and__(BaseIntervalSet self, other):
        if self.__class__ is not other.__class__:
            return NotImplemented
        return self.intersection(other)
    
    def __or__(BaseIntervalSet self, other):
        if self.__class__ is not other.__class__:
            return NotImplemented
        return self.union(other)
    
    def __ror__(BaseIntervalSet self, other):
        if self.__class__ is not other.__class__:
            return NotImplemented
        return other.__or__(self)
    
    def __rand__(BaseIntervalSet self, other):
        if self.__class__ is not other.__class__:
            return NotImplemented
        return other.__and__(other)
    
    def __sub__(BaseIntervalSet self, other):
        if self.__class__ is not other.__class__:
            return NotImplemented
        return self.minus(other)
    
    def __rsub__(BaseIntervalSet self, other):
        if self.__class__ is not other.__class__:
            return NotImplemented
        return other.__sub__(self)
    
    def __invert__(BaseIntervalSet self):
        return self.complement()
    
    def __nonzero__(BaseIntervalSet self):
        return not self.empty()
    
    def __reduce__(BaseIntervalSet self):
        return (self.__class__, self.init_args())
    
    def __hash__(BaseIntervalSet self):
        return hash(self.__reduce__())
    
cdef class BaseIntervalSetIterator:
    pass

cdef timedelta day = timedelta(days=1)


cdef class ObjectInterval(BaseInterval):
    def __init__(BaseInterval self, object lower_bound, object upper_bound, bool lower_closed, 
                 bool upper_closed, bool lower_bounded, bool upper_bounded):
        self.lower_closed = lower_closed
        self.upper_closed = upper_closed
        self.lower_bounded = lower_bounded
        self.upper_bounded = upper_bounded
        if lower_bounded:
            self.lower_bound = lower_bound
        if upper_bounded:
            self.upper_bound = upper_bound
    
    # For some types, there is a concept of adjacent elements.  For example, 
    # there are no integers between 1 and 2 (although there are several real numbers).
    # If there is such a concept, it's possible for an interval to be empty even when 
    # the lower bound is strictly less than the upper bound, provided the bounds are strict 
    # (not closed).  The adjacent method is used to help determine such cases.
    cpdef bool adjacent(ObjectInterval self, object lower, object upper):
        return False
    
    cpdef int containment_cmp(ObjectInterval self, object item):
        if self.lower_bounded:
            if item < self.lower_bound:
                return -1
            elif item == self.lower_bound:
                if not self.lower_closed:
                    return -1
        # If we get here, the item satisfies the lower bound constraint
        if self.upper_bounded:
            if item > self.upper_bound:
                return 1
            elif item == self.upper_bound:
                if not self.upper_closed:
                    return 1
        # If we get here, the item also satisfies the upper bound constraint
        return 0
    
    cpdef bool contains(ObjectInterval self, object item):
        return self.containment_cmp(item) == 0
    
    cpdef bool subset(ObjectInterval self, ObjectInterval other):
        '''
        Return True if and only if self is a subset of other.
        '''
        cdef int lower_cmp, upper_cmp
        lower_cmp = self.lower_cmp(other)
        upper_cmp = self.upper_cmp(other)
        return lower_cmp >= 0 and upper_cmp <= 0
        
    cpdef int overlap_cmp(ObjectInterval self, ObjectInterval other):
        '''
        Assume both are nonempty.  Return -1 if every element of self is less than every 
        element of other.  Return 0 if self and other intersect.  Return 1 if every element of 
        self is greater than every element of other.
        '''
        cdef int lower_cmp, upper_cmp
        lower_cmp = self.lower_cmp(other)
        upper_cmp = self.upper_cmp(other)
        
        if self.upper_bounded and other.lower_bounded:
            if self.upper_bound < other.lower_bound:
                return -1
            elif self.upper_bound == other.lower_bound:
                if self.upper_closed and other.lower_closed:
                    return 0
                else:
                    return -1
        if self.lower_bounded and other.upper_bounded:
            if self.lower_bound > other.upper_bound:
                return 1
            elif self.lower_bound == other.upper_bound:
                if self.lower_closed and other.upper_closed:
                    return 0
                else:
                    return 1
        return 0
    
    cpdef tuple init_args(ObjectInterval self):
        return (self.lower_bound, self.upper_bound, self.lower_closed, self.upper_closed, 
                self.lower_bounded, self.upper_bounded)

    cpdef ObjectInterval intersection(ObjectInterval self, ObjectInterval other):
        cdef int lower_cmp = self.lower_cmp(other)
        cdef int upper_cmp = self.upper_cmp(other)
        cdef object new_lower_bound, new_upper_bound
        cdef bool new_lower_closed, new_lower_bounded, new_upper_closed, new_upper_bounded
        if lower_cmp <= 0:
            new_lower_bound = other.lower_bound
            new_lower_bounded = other.lower_bounded
            new_lower_closed = other.lower_closed
        else:
            new_lower_bound = self.lower_bound
            new_lower_bounded = self.lower_bounded
            new_lower_closed = self.lower_closed
        
        if upper_cmp <= 0:
            new_upper_bound = self.upper_bound
            new_upper_bounded = self.upper_bounded
            new_upper_closed = self.upper_closed
        else:
            new_upper_bound = other.upper_bound
            new_upper_bounded = other.upper_bounded
            new_upper_closed = other.upper_closed
        return ObjectInterval(new_lower_bound, new_upper_bound, new_lower_closed, 
                               new_upper_closed, new_lower_bounded, new_upper_bounded)
    
    cpdef ObjectInterval fusion(ObjectInterval self, ObjectInterval other):
        '''
        Assume union of intervals is a single interval.  Return their union.  Results not correct
        if above assumption is violated.
        '''
        cdef int lower_cmp = self.lower_cmp(other)
        cdef int upper_cmp = self.upper_cmp(other)
        cdef object new_lower_bound, new_upper_bound
        cdef bool new_lower_closed, new_lower_bounded, new_upper_closed, new_upper_bounded
        if lower_cmp <= 0:
            new_lower_bound = self.lower_bound
            new_lower_bounded = self.lower_bounded
            new_lower_closed = self.lower_closed
        else:
            new_lower_bound = other.lower_bound
            new_lower_bounded = other.lower_bounded
            new_lower_closed = other.lower_closed
        
        if upper_cmp <= 0:
            new_upper_bound = other.upper_bound
            new_upper_bounded = other.upper_bounded
            new_upper_closed = other.upper_closed
        else:
            new_upper_bound = self.upper_bound
            new_upper_bounded = self.upper_bounded
            new_upper_closed = self.upper_closed
        return ObjectInterval(new_lower_bound, new_upper_bound, new_lower_closed, 
                               new_upper_closed, new_lower_bounded, new_upper_bounded)
    
    cpdef bool empty(ObjectInterval self):
        return ((self.lower_bounded and self.upper_bounded) and 
                ((((self.lower_bound == self.upper_bound) and 
                (not (self.lower_closed and self.upper_closed))) or
                self.lower_bound > self.upper_bound) or 
                 (self.lower_bound < self.upper_bound and 
                  (not (self.lower_closed or self.upper_closed)) and
                  self.adjacent(self.lower_bound, self.upper_bound))))
    
    cpdef bool richcmp(ObjectInterval self, ObjectInterval other, int op):
        cdef int lower_cmp
        cdef int upper_cmp
        if op == 0 or op == 1:
            lower_cmp = self.lower_cmp(other)
            if lower_cmp == -1:
                return True
            elif lower_cmp == 1:
                return False
            else: # lower_cmp == 0
                upper_cmp = self.upper_cmp(other)
                if upper_cmp == -1:
                    return True
                elif upper_cmp == 1:
                    return False
                else: # upper_cmp == 0
                    return op == 1
        elif op == 2:
            return (self.lower_cmp(other) == 0) and (self.upper_cmp(other) == 0)
        elif op == 3:
            return (self.lower_cmp(other) != 0) or (self.upper_cmp(other) != 0)
        elif op == 4 or op == 5:
            lower_cmp = self.lower_cmp(other)
            if lower_cmp == -1:
                return False
            elif lower_cmp == 1:
                return True
            else: # lower_cmp == 0
                upper_cmp = self.upper_cmp(other)
                if upper_cmp == -1:
                    return False
                elif upper_cmp == 1:
                    return True
                else: # upper_cmp == 0
                    return op == 5
    
    cpdef int lower_cmp(ObjectInterval self, ObjectInterval other):
        if not self.lower_bounded:
            if not other.lower_bounded:
                return 0
            else:
                return -1
        elif not other.lower_bounded:
            return 1
        if self.lower_bound < other.lower_bound:
            return -1
        elif self.lower_bound == other.lower_bound:
            if self.lower_closed and not other.lower_closed:
                return -1
            elif other.lower_closed and not self.lower_closed:
                return 1
            else:
                return 0
        else:
            return 1
    
    cpdef int upper_cmp(ObjectInterval self, ObjectInterval other):
        if not self.upper_bounded:
            if not other.upper_bounded:
                return 0
            else:
                return 1
        elif not other.upper_bounded:
            return -1
        if self.upper_bound < other.upper_bound:
            return -1
        elif self.upper_bound == other.upper_bound:
            if self.upper_closed and not other.upper_closed:
                return 1
            elif other.upper_closed and not self.upper_closed:
                return -1
            else:
                return 0
        else:
            return 1

# This is because static cpdef methods are not supported.  Otherwise this
# would be a static method of ObjectIntervalSet
cpdef tuple ObjectInterval_preprocess_intervals(tuple intervals):
    # Remove any empty intervals
    cdef ObjectInterval interval
    
    cdef list tmp = []
    for interval in intervals:
        if not interval.empty():
            tmp.append(interval)
    
    # If there are no nonempty intervals, return
    if not tmp:
        return tuple()
    
    # Sort
    tmp.sort()
    
    # Fuse any overlapping intervals
    cdef list tmp2 = []
    cdef ObjectInterval interval2
    cdef int overlap_cmp
    interval = tmp[0]
    for interval2 in tmp[1:]:
        overlap_cmp = interval.overlap_cmp(interval2)
        if (
            (overlap_cmp == 0) or 
            (overlap_cmp == -1 and interval.upper_bound == interval2.lower_bound and (interval.upper_closed or interval2.lower_closed)) or
            (overlap_cmp == 1 and interval2.upper_bound == interval.lower_bound and (interval2.upper_closed or interval.lower_closed))
            ):
            interval = interval.fusion(interval2)
        else:
            tmp2.append(interval)
            interval = interval2
    tmp2.append(interval)
    return tuple(tmp2)

cdef class ObjectIntervalSetIterator(BaseIntervalSetIterator):
    def __init__(ObjectIntervalSetIterator self, ObjectIntervalSet interval_set):
        self.index = 0
        self.interval_set = interval_set
    
    def __iter__(ObjectIntervalSetIterator self):
        return self
    
    def __next__(ObjectIntervalSetIterator self):
        self.index += 1
        if self.index <= self.interval_set.n_intervals:
            return self.interval_set.intervals[self.index-1]
        raise StopIteration

cdef class ObjectIntervalSet(BaseIntervalSet):
    def __init__(ObjectIntervalSet self, tuple intervals):
        '''
        The intervals must already be sorted and non-overlapping.
        '''
        self.intervals = intervals
        self.n_intervals = len(intervals)
    
    def __iter__(ObjectIntervalSet self):
        return ObjectIntervalSetIterator(self)
    
    def __getitem__(ObjectIntervalSet self, index):
        return self.intervals[index]
    
    cpdef bool lower_bounded(ObjectIntervalSet self):
        cdef ObjectInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[0]
            return interval.lower_bounded
        else:
            return True
    
    cpdef bool upper_bounded(ObjectIntervalSet self):
        cdef ObjectInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[self.n_intervals - 1]
            return interval.upper_bounded
        else:
            return True
    
    cpdef object lower_bound(ObjectIntervalSet self):
        cdef ObjectInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[0]
            return interval.lower_bound
        else:
            return None
    
    cpdef object upper_bound(ObjectIntervalSet self):
        cdef ObjectInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[self.n_intervals - 1]
            return interval.upper_bound
        else:
            return None
    
    cpdef tuple init_args(ObjectIntervalSet self):
        return (self.intervals,)
    
    cpdef bool contains(ObjectIntervalSet self, object item):
        '''
        Use binary search to determine whether item is in self.
        '''
        cdef int i, n
        cdef int low, high
        cdef int cmp
        cdef ObjectInterval interval 
        n = self.n_intervals
        low = 0
        high = n-1
        while high >= low:
            i = (high + low) / 2
            interval = self.intervals[i]
            cmp = interval.containment_cmp(item)
            if cmp == -1:
                high = i - 1
            elif cmp == 1:
                low = i + 1
            else: #if cmp == 0:
                return True
        return False

    cpdef bool subset(ObjectIntervalSet self, ObjectIntervalSet other):
        '''
        Return True if and only if self is a subset of other.
        '''
        cdef ObjectInterval self_interval, other_interval
        cdef int i, j, m, n
        cdef int overlap_cmp, cmp
        if self.empty():
            return True
        elif other.empty():
            return False
        m = self.n_intervals
        n = other.n_intervals
        j = 0
        other_interval = other.intervals[j]
        for i in range(m):
            self_interval = self.intervals[i]
            overlap_cmp = self_interval.overlap_cmp(other_interval)
            if overlap_cmp == -1:
                return False
            elif overlap_cmp == 0:
                if not self_interval.subset(other_interval):
                    return False
            elif overlap_cmp == 1:
                if j < n-1:
                    j += 1
                    other_interval = other.intervals[j]
                else:
                    return False
        return True
    
    cpdef bool equal(ObjectIntervalSet self, ObjectIntervalSet other):
        cdef ObjectInterval self_interval, other_interval
        cdef int i, n
        n = self.n_intervals
        if n != other.n_intervals:
            return False
        for i in range(n):
            self_interval = self.intervals[i]
            other_interval = other.intervals[i]
            if not self_interval.richcmp(other_interval, 2):
                return False
        return True
    
    cpdef bool richcmp(ObjectIntervalSet self, ObjectIntervalSet other, int op):
        if op == 0:
            return self.subset(other) and not self.equal(other)
        elif op == 1:
            return self.subset(other)
        elif op == 2:
            return self.equal(other)
        elif op == 3:
            return not self.equal(other)
        elif op == 4:
            return other.subset(self) and not other.equal(self)
        elif op == 5:
            return other.subset(self)
    
    cpdef bool empty(ObjectIntervalSet self):
        return self.n_intervals == 0 
    
    cpdef ObjectIntervalSet intersection(ObjectIntervalSet self, ObjectIntervalSet other):
        if self.empty() or other.empty():
            return self
        cdef int i, j, m, n, cmp, upper_cmp
        i = 0
        j = 0
        m = self.n_intervals
        n = other.n_intervals
        cdef ObjectInterval interval1, interval2
        interval1 = self.intervals[i]
        interval2 = other.intervals[j]
        cdef list new_intervals = []
        while True:
            cmp = interval1.overlap_cmp(interval2)
            if cmp == -1:
                i += 1
                if i <= m-1:
                    interval1 = self.intervals[i]
                else:
                    break
            elif cmp == 1:
                j += 1
                if j <= n-1:
                    interval2 = other.intervals[j]
                else:
                    break
            else:
                new_intervals.append(interval1.intersection(interval2))
                upper_cmp = interval1.upper_cmp(interval2)
                if upper_cmp <= 0:
                    i += 1
                    if i <= m-1:
                        interval1 = self.intervals[i]
                    else:
                        break
                if upper_cmp >= 0:
                    j += 1
                    if j <= n-1:
                        interval2 = other.intervals[j]
                    else:
                        break
        return ObjectIntervalSet(tuple(new_intervals))
    
    cpdef ObjectIntervalSet union(ObjectIntervalSet self, ObjectIntervalSet other):
        cdef ObjectInterval new_interval, interval1, interval2, next_interval
        if self.empty():
            return other
        if other.empty():
            return self
        interval1 = self.intervals[0]
        interval2 = other.intervals[0]
        
        cdef int i, j, m, n, cmp
        cdef bool richcmp, first = True
        i = 0
        j = 0
        m = self.n_intervals
        n = other.n_intervals
        cdef list new_intervals = []
        while i < m or j < n:
            if i == m:
                richcmp = False
            elif j == n:
                richcmp = True
            else:
                richcmp = interval1.richcmp(interval2, 1)
            if richcmp:
                next_interval = interval1 
                i += 1
                if i < m:
                    interval1 = self.intervals[i]
            else:
                next_interval = interval2
                j += 1
                if j < n:
                    interval2 = other.intervals[j]
            if first:
                first = False
                new_interval = next_interval
            else:
                cmp = new_interval.overlap_cmp(next_interval)
                if (cmp == 0 or 
                (cmp==-1 and new_interval.upper_bound == next_interval.lower_bound and 
                 (new_interval.upper_closed or next_interval.lower_closed)) or 
                 (cmp==1 and new_interval.lower_bound == next_interval.upper_bound and 
                 (new_interval.lower_closed or next_interval.upper_closed))):
                    new_interval = new_interval.fusion(next_interval)
                else:
                    new_intervals.append(new_interval)
                    new_interval = next_interval
        new_intervals.append(new_interval)
        return ObjectIntervalSet(tuple(new_intervals))
    
    cpdef ObjectIntervalSet complement(ObjectIntervalSet self):
        if self.empty():
            return ObjectIntervalSet((ObjectInterval(None, None, True, True, False, False),))
        cdef ObjectInterval interval, previous
        cdef int i
        cdef n = self.n_intervals
        interval = self.intervals[0]
        cdef list new_intervals = []
        if interval.lower_bounded:
            new_intervals.append(ObjectInterval(None, interval.lower_bound, 
                                                 True, not interval.lower_closed, False, True))
        previous = interval
        for i in range(1,n):
            interval = self.intervals[i]
            new_intervals.append(ObjectInterval(previous.upper_bound, interval.lower_bound, not previous.upper_closed, 
                                                 not interval.lower_closed, True, True))
            previous = interval
        interval = self.intervals[n-1]
        if interval.upper_bounded:
            new_intervals.append(ObjectInterval(interval.upper_bound, None, not interval.upper_closed, True, 
                                                 True, False))
        return ObjectIntervalSet(tuple(new_intervals))
            
    cpdef ObjectIntervalSet minus(ObjectIntervalSet self, ObjectIntervalSet other):
        return self.intersection(other.complement())

cdef class DateInterval(BaseInterval):
    def __init__(BaseInterval self, date lower_bound, date upper_bound, bool lower_closed, 
                 bool upper_closed, bool lower_bounded, bool upper_bounded):
        self.lower_closed = lower_closed
        self.upper_closed = upper_closed
        self.lower_bounded = lower_bounded
        self.upper_bounded = upper_bounded
        if lower_bounded:
            self.lower_bound = lower_bound
        if upper_bounded:
            self.upper_bound = upper_bound
    
    # For some types, there is a concept of adjacent elements.  For example, 
    # there are no integers between 1 and 2 (although there are several real numbers).
    # If there is such a concept, it's possible for an interval to be empty even when 
    # the lower bound is strictly less than the upper bound, provided the bounds are strict 
    # (not closed).  The adjacent method is used to help determine such cases.
    cpdef bool adjacent(DateInterval self, date lower, date upper):
        return lower + day == upper
    
    cpdef int containment_cmp(DateInterval self, date item):
        if self.lower_bounded:
            if item < self.lower_bound:
                return -1
            elif item == self.lower_bound:
                if not self.lower_closed:
                    return -1
        # If we get here, the item satisfies the lower bound constraint
        if self.upper_bounded:
            if item > self.upper_bound:
                return 1
            elif item == self.upper_bound:
                if not self.upper_closed:
                    return 1
        # If we get here, the item also satisfies the upper bound constraint
        return 0
    
    cpdef bool contains(DateInterval self, date item):
        return self.containment_cmp(item) == 0
    
    cpdef bool subset(DateInterval self, DateInterval other):
        '''
        Return True if and only if self is a subset of other.
        '''
        cdef int lower_cmp, upper_cmp
        lower_cmp = self.lower_cmp(other)
        upper_cmp = self.upper_cmp(other)
        return lower_cmp >= 0 and upper_cmp <= 0
        
    cpdef int overlap_cmp(DateInterval self, DateInterval other):
        '''
        Assume both are nonempty.  Return -1 if every element of self is less than every 
        element of other.  Return 0 if self and other intersect.  Return 1 if every element of 
        self is greater than every element of other.
        '''
        cdef int lower_cmp, upper_cmp
        lower_cmp = self.lower_cmp(other)
        upper_cmp = self.upper_cmp(other)
        
        if self.upper_bounded and other.lower_bounded:
            if self.upper_bound < other.lower_bound:
                return -1
            elif self.upper_bound == other.lower_bound:
                if self.upper_closed and other.lower_closed:
                    return 0
                else:
                    return -1
        if self.lower_bounded and other.upper_bounded:
            if self.lower_bound > other.upper_bound:
                return 1
            elif self.lower_bound == other.upper_bound:
                if self.lower_closed and other.upper_closed:
                    return 0
                else:
                    return 1
        return 0
    
    cpdef tuple init_args(DateInterval self):
        return (self.lower_bound, self.upper_bound, self.lower_closed, self.upper_closed, 
                self.lower_bounded, self.upper_bounded)

    cpdef DateInterval intersection(DateInterval self, DateInterval other):
        cdef int lower_cmp = self.lower_cmp(other)
        cdef int upper_cmp = self.upper_cmp(other)
        cdef date new_lower_bound, new_upper_bound
        cdef bool new_lower_closed, new_lower_bounded, new_upper_closed, new_upper_bounded
        if lower_cmp <= 0:
            new_lower_bound = other.lower_bound
            new_lower_bounded = other.lower_bounded
            new_lower_closed = other.lower_closed
        else:
            new_lower_bound = self.lower_bound
            new_lower_bounded = self.lower_bounded
            new_lower_closed = self.lower_closed
        
        if upper_cmp <= 0:
            new_upper_bound = self.upper_bound
            new_upper_bounded = self.upper_bounded
            new_upper_closed = self.upper_closed
        else:
            new_upper_bound = other.upper_bound
            new_upper_bounded = other.upper_bounded
            new_upper_closed = other.upper_closed
        return DateInterval(new_lower_bound, new_upper_bound, new_lower_closed, 
                               new_upper_closed, new_lower_bounded, new_upper_bounded)
    
    cpdef DateInterval fusion(DateInterval self, DateInterval other):
        '''
        Assume union of intervals is a single interval.  Return their union.  Results not correct
        if above assumption is violated.
        '''
        cdef int lower_cmp = self.lower_cmp(other)
        cdef int upper_cmp = self.upper_cmp(other)
        cdef date new_lower_bound, new_upper_bound
        cdef bool new_lower_closed, new_lower_bounded, new_upper_closed, new_upper_bounded
        if lower_cmp <= 0:
            new_lower_bound = self.lower_bound
            new_lower_bounded = self.lower_bounded
            new_lower_closed = self.lower_closed
        else:
            new_lower_bound = other.lower_bound
            new_lower_bounded = other.lower_bounded
            new_lower_closed = other.lower_closed
        
        if upper_cmp <= 0:
            new_upper_bound = other.upper_bound
            new_upper_bounded = other.upper_bounded
            new_upper_closed = other.upper_closed
        else:
            new_upper_bound = self.upper_bound
            new_upper_bounded = self.upper_bounded
            new_upper_closed = self.upper_closed
        return DateInterval(new_lower_bound, new_upper_bound, new_lower_closed, 
                               new_upper_closed, new_lower_bounded, new_upper_bounded)
    
    cpdef bool empty(DateInterval self):
        return ((self.lower_bounded and self.upper_bounded) and 
                ((((self.lower_bound == self.upper_bound) and 
                (not (self.lower_closed and self.upper_closed))) or
                self.lower_bound > self.upper_bound) or 
                 (self.lower_bound < self.upper_bound and 
                  (not (self.lower_closed or self.upper_closed)) and
                  self.adjacent(self.lower_bound, self.upper_bound))))
    
    cpdef bool richcmp(DateInterval self, DateInterval other, int op):
        cdef int lower_cmp
        cdef int upper_cmp
        if op == 0 or op == 1:
            lower_cmp = self.lower_cmp(other)
            if lower_cmp == -1:
                return True
            elif lower_cmp == 1:
                return False
            else: # lower_cmp == 0
                upper_cmp = self.upper_cmp(other)
                if upper_cmp == -1:
                    return True
                elif upper_cmp == 1:
                    return False
                else: # upper_cmp == 0
                    return op == 1
        elif op == 2:
            return (self.lower_cmp(other) == 0) and (self.upper_cmp(other) == 0)
        elif op == 3:
            return (self.lower_cmp(other) != 0) or (self.upper_cmp(other) != 0)
        elif op == 4 or op == 5:
            lower_cmp = self.lower_cmp(other)
            if lower_cmp == -1:
                return False
            elif lower_cmp == 1:
                return True
            else: # lower_cmp == 0
                upper_cmp = self.upper_cmp(other)
                if upper_cmp == -1:
                    return False
                elif upper_cmp == 1:
                    return True
                else: # upper_cmp == 0
                    return op == 5
    
    cpdef int lower_cmp(DateInterval self, DateInterval other):
        if not self.lower_bounded:
            if not other.lower_bounded:
                return 0
            else:
                return -1
        elif not other.lower_bounded:
            return 1
        if self.lower_bound < other.lower_bound:
            return -1
        elif self.lower_bound == other.lower_bound:
            if self.lower_closed and not other.lower_closed:
                return -1
            elif other.lower_closed and not self.lower_closed:
                return 1
            else:
                return 0
        else:
            return 1
    
    cpdef int upper_cmp(DateInterval self, DateInterval other):
        if not self.upper_bounded:
            if not other.upper_bounded:
                return 0
            else:
                return 1
        elif not other.upper_bounded:
            return -1
        if self.upper_bound < other.upper_bound:
            return -1
        elif self.upper_bound == other.upper_bound:
            if self.upper_closed and not other.upper_closed:
                return 1
            elif other.upper_closed and not self.upper_closed:
                return -1
            else:
                return 0
        else:
            return 1

# This is because static cpdef methods are not supported.  Otherwise this
# would be a static method of DateIntervalSet
cpdef tuple DateInterval_preprocess_intervals(tuple intervals):
    # Remove any empty intervals
    cdef DateInterval interval
    
    cdef list tmp = []
    for interval in intervals:
        if not interval.empty():
            tmp.append(interval)
    
    # If there are no nonempty intervals, return
    if not tmp:
        return tuple()
    
    # Sort
    tmp.sort()
    
    # Fuse any overlapping intervals
    cdef list tmp2 = []
    cdef DateInterval interval2
    cdef int overlap_cmp
    interval = tmp[0]
    for interval2 in tmp[1:]:
        overlap_cmp = interval.overlap_cmp(interval2)
        if (
            (overlap_cmp == 0) or 
            (overlap_cmp == -1 and interval.upper_bound == interval2.lower_bound and (interval.upper_closed or interval2.lower_closed)) or
            (overlap_cmp == 1 and interval2.upper_bound == interval.lower_bound and (interval2.upper_closed or interval.lower_closed))
            ):
            interval = interval.fusion(interval2)
        else:
            tmp2.append(interval)
            interval = interval2
    tmp2.append(interval)
    return tuple(tmp2)

cdef class DateIntervalSetIterator(BaseIntervalSetIterator):
    def __init__(DateIntervalSetIterator self, DateIntervalSet interval_set):
        self.index = 0
        self.interval_set = interval_set
    
    def __iter__(DateIntervalSetIterator self):
        return self
    
    def __next__(DateIntervalSetIterator self):
        self.index += 1
        if self.index <= self.interval_set.n_intervals:
            return self.interval_set.intervals[self.index-1]
        raise StopIteration

cdef class DateIntervalSet(BaseIntervalSet):
    def __init__(DateIntervalSet self, tuple intervals):
        '''
        The intervals must already be sorted and non-overlapping.
        '''
        self.intervals = intervals
        self.n_intervals = len(intervals)
    
    def __iter__(DateIntervalSet self):
        return DateIntervalSetIterator(self)
    
    def __getitem__(DateIntervalSet self, index):
        return self.intervals[index]
    
    cpdef bool lower_bounded(DateIntervalSet self):
        cdef DateInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[0]
            return interval.lower_bounded
        else:
            return True
    
    cpdef bool upper_bounded(DateIntervalSet self):
        cdef DateInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[self.n_intervals - 1]
            return interval.upper_bounded
        else:
            return True
    
    cpdef date lower_bound(DateIntervalSet self):
        cdef DateInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[0]
            return interval.lower_bound
        else:
            return None
    
    cpdef date upper_bound(DateIntervalSet self):
        cdef DateInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[self.n_intervals - 1]
            return interval.upper_bound
        else:
            return None
    
    cpdef tuple init_args(DateIntervalSet self):
        return (self.intervals,)
    
    cpdef bool contains(DateIntervalSet self, date item):
        '''
        Use binary search to determine whether item is in self.
        '''
        cdef int i, n
        cdef int low, high
        cdef int cmp
        cdef DateInterval interval 
        n = self.n_intervals
        low = 0
        high = n-1
        while high >= low:
            i = (high + low) / 2
            interval = self.intervals[i]
            cmp = interval.containment_cmp(item)
            if cmp == -1:
                high = i - 1
            elif cmp == 1:
                low = i + 1
            else: #if cmp == 0:
                return True
        return False

    cpdef bool subset(DateIntervalSet self, DateIntervalSet other):
        '''
        Return True if and only if self is a subset of other.
        '''
        cdef DateInterval self_interval, other_interval
        cdef int i, j, m, n
        cdef int overlap_cmp, cmp
        if self.empty():
            return True
        elif other.empty():
            return False
        m = self.n_intervals
        n = other.n_intervals
        j = 0
        other_interval = other.intervals[j]
        for i in range(m):
            self_interval = self.intervals[i]
            overlap_cmp = self_interval.overlap_cmp(other_interval)
            if overlap_cmp == -1:
                return False
            elif overlap_cmp == 0:
                if not self_interval.subset(other_interval):
                    return False
            elif overlap_cmp == 1:
                if j < n-1:
                    j += 1
                    other_interval = other.intervals[j]
                else:
                    return False
        return True
    
    cpdef bool equal(DateIntervalSet self, DateIntervalSet other):
        cdef DateInterval self_interval, other_interval
        cdef int i, n
        n = self.n_intervals
        if n != other.n_intervals:
            return False
        for i in range(n):
            self_interval = self.intervals[i]
            other_interval = other.intervals[i]
            if not self_interval.richcmp(other_interval, 2):
                return False
        return True
    
    cpdef bool richcmp(DateIntervalSet self, DateIntervalSet other, int op):
        if op == 0:
            return self.subset(other) and not self.equal(other)
        elif op == 1:
            return self.subset(other)
        elif op == 2:
            return self.equal(other)
        elif op == 3:
            return not self.equal(other)
        elif op == 4:
            return other.subset(self) and not other.equal(self)
        elif op == 5:
            return other.subset(self)
    
    cpdef bool empty(DateIntervalSet self):
        return self.n_intervals == 0 
    
    cpdef DateIntervalSet intersection(DateIntervalSet self, DateIntervalSet other):
        if self.empty() or other.empty():
            return self
        cdef int i, j, m, n, cmp, upper_cmp
        i = 0
        j = 0
        m = self.n_intervals
        n = other.n_intervals
        cdef DateInterval interval1, interval2
        interval1 = self.intervals[i]
        interval2 = other.intervals[j]
        cdef list new_intervals = []
        while True:
            cmp = interval1.overlap_cmp(interval2)
            if cmp == -1:
                i += 1
                if i <= m-1:
                    interval1 = self.intervals[i]
                else:
                    break
            elif cmp == 1:
                j += 1
                if j <= n-1:
                    interval2 = other.intervals[j]
                else:
                    break
            else:
                new_intervals.append(interval1.intersection(interval2))
                upper_cmp = interval1.upper_cmp(interval2)
                if upper_cmp <= 0:
                    i += 1
                    if i <= m-1:
                        interval1 = self.intervals[i]
                    else:
                        break
                if upper_cmp >= 0:
                    j += 1
                    if j <= n-1:
                        interval2 = other.intervals[j]
                    else:
                        break
        return DateIntervalSet(tuple(new_intervals))
    
    cpdef DateIntervalSet union(DateIntervalSet self, DateIntervalSet other):
        cdef DateInterval new_interval, interval1, interval2, next_interval
        if self.empty():
            return other
        if other.empty():
            return self
        interval1 = self.intervals[0]
        interval2 = other.intervals[0]
        
        cdef int i, j, m, n, cmp
        cdef bool richcmp, first = True
        i = 0
        j = 0
        m = self.n_intervals
        n = other.n_intervals
        cdef list new_intervals = []
        while i < m or j < n:
            if i == m:
                richcmp = False
            elif j == n:
                richcmp = True
            else:
                richcmp = interval1.richcmp(interval2, 1)
            if richcmp:
                next_interval = interval1 
                i += 1
                if i < m:
                    interval1 = self.intervals[i]
            else:
                next_interval = interval2
                j += 1
                if j < n:
                    interval2 = other.intervals[j]
            if first:
                first = False
                new_interval = next_interval
            else:
                cmp = new_interval.overlap_cmp(next_interval)
                if (cmp == 0 or 
                (cmp==-1 and new_interval.upper_bound == next_interval.lower_bound and 
                 (new_interval.upper_closed or next_interval.lower_closed)) or 
                 (cmp==1 and new_interval.lower_bound == next_interval.upper_bound and 
                 (new_interval.lower_closed or next_interval.upper_closed))):
                    new_interval = new_interval.fusion(next_interval)
                else:
                    new_intervals.append(new_interval)
                    new_interval = next_interval
        new_intervals.append(new_interval)
        return DateIntervalSet(tuple(new_intervals))
    
    cpdef DateIntervalSet complement(DateIntervalSet self):
        if self.empty():
            return DateIntervalSet((DateInterval(None, None, True, True, False, False),))
        cdef DateInterval interval, previous
        cdef int i
        cdef n = self.n_intervals
        interval = self.intervals[0]
        cdef list new_intervals = []
        if interval.lower_bounded:
            new_intervals.append(DateInterval(None, interval.lower_bound, 
                                                 True, not interval.lower_closed, False, True))
        previous = interval
        for i in range(1,n):
            interval = self.intervals[i]
            new_intervals.append(DateInterval(previous.upper_bound, interval.lower_bound, not previous.upper_closed, 
                                                 not interval.lower_closed, True, True))
            previous = interval
        interval = self.intervals[n-1]
        if interval.upper_bounded:
            new_intervals.append(DateInterval(interval.upper_bound, None, not interval.upper_closed, True, 
                                                 True, False))
        return DateIntervalSet(tuple(new_intervals))
            
    cpdef DateIntervalSet minus(DateIntervalSet self, DateIntervalSet other):
        return self.intersection(other.complement())

cdef class IntInterval(BaseInterval):
    def __init__(BaseInterval self, int lower_bound, int upper_bound, bool lower_closed, 
                 bool upper_closed, bool lower_bounded, bool upper_bounded):
        self.lower_closed = lower_closed
        self.upper_closed = upper_closed
        self.lower_bounded = lower_bounded
        self.upper_bounded = upper_bounded
        if lower_bounded:
            self.lower_bound = lower_bound
        if upper_bounded:
            self.upper_bound = upper_bound
    
    # For some types, there is a concept of adjacent elements.  For example, 
    # there are no integers between 1 and 2 (although there are several real numbers).
    # If there is such a concept, it's possible for an interval to be empty even when 
    # the lower bound is strictly less than the upper bound, provided the bounds are strict 
    # (not closed).  The adjacent method is used to help determine such cases.
    cpdef bool adjacent(IntInterval self, int lower, int upper):
        return lower + 1 == upper
    
    cpdef int containment_cmp(IntInterval self, int item):
        if self.lower_bounded:
            if item < self.lower_bound:
                return -1
            elif item == self.lower_bound:
                if not self.lower_closed:
                    return -1
        # If we get here, the item satisfies the lower bound constraint
        if self.upper_bounded:
            if item > self.upper_bound:
                return 1
            elif item == self.upper_bound:
                if not self.upper_closed:
                    return 1
        # If we get here, the item also satisfies the upper bound constraint
        return 0
    
    cpdef bool contains(IntInterval self, int item):
        return self.containment_cmp(item) == 0
    
    cpdef bool subset(IntInterval self, IntInterval other):
        '''
        Return True if and only if self is a subset of other.
        '''
        cdef int lower_cmp, upper_cmp
        lower_cmp = self.lower_cmp(other)
        upper_cmp = self.upper_cmp(other)
        return lower_cmp >= 0 and upper_cmp <= 0
        
    cpdef int overlap_cmp(IntInterval self, IntInterval other):
        '''
        Assume both are nonempty.  Return -1 if every element of self is less than every 
        element of other.  Return 0 if self and other intersect.  Return 1 if every element of 
        self is greater than every element of other.
        '''
        cdef int lower_cmp, upper_cmp
        lower_cmp = self.lower_cmp(other)
        upper_cmp = self.upper_cmp(other)
        
        if self.upper_bounded and other.lower_bounded:
            if self.upper_bound < other.lower_bound:
                return -1
            elif self.upper_bound == other.lower_bound:
                if self.upper_closed and other.lower_closed:
                    return 0
                else:
                    return -1
        if self.lower_bounded and other.upper_bounded:
            if self.lower_bound > other.upper_bound:
                return 1
            elif self.lower_bound == other.upper_bound:
                if self.lower_closed and other.upper_closed:
                    return 0
                else:
                    return 1
        return 0
    
    cpdef tuple init_args(IntInterval self):
        return (self.lower_bound, self.upper_bound, self.lower_closed, self.upper_closed, 
                self.lower_bounded, self.upper_bounded)

    cpdef IntInterval intersection(IntInterval self, IntInterval other):
        cdef int lower_cmp = self.lower_cmp(other)
        cdef int upper_cmp = self.upper_cmp(other)
        cdef int new_lower_bound, new_upper_bound
        cdef bool new_lower_closed, new_lower_bounded, new_upper_closed, new_upper_bounded
        if lower_cmp <= 0:
            new_lower_bound = other.lower_bound
            new_lower_bounded = other.lower_bounded
            new_lower_closed = other.lower_closed
        else:
            new_lower_bound = self.lower_bound
            new_lower_bounded = self.lower_bounded
            new_lower_closed = self.lower_closed
        
        if upper_cmp <= 0:
            new_upper_bound = self.upper_bound
            new_upper_bounded = self.upper_bounded
            new_upper_closed = self.upper_closed
        else:
            new_upper_bound = other.upper_bound
            new_upper_bounded = other.upper_bounded
            new_upper_closed = other.upper_closed
        return IntInterval(new_lower_bound, new_upper_bound, new_lower_closed, 
                               new_upper_closed, new_lower_bounded, new_upper_bounded)
    
    cpdef IntInterval fusion(IntInterval self, IntInterval other):
        '''
        Assume union of intervals is a single interval.  Return their union.  Results not correct
        if above assumption is violated.
        '''
        cdef int lower_cmp = self.lower_cmp(other)
        cdef int upper_cmp = self.upper_cmp(other)
        cdef int new_lower_bound, new_upper_bound
        cdef bool new_lower_closed, new_lower_bounded, new_upper_closed, new_upper_bounded
        if lower_cmp <= 0:
            new_lower_bound = self.lower_bound
            new_lower_bounded = self.lower_bounded
            new_lower_closed = self.lower_closed
        else:
            new_lower_bound = other.lower_bound
            new_lower_bounded = other.lower_bounded
            new_lower_closed = other.lower_closed
        
        if upper_cmp <= 0:
            new_upper_bound = other.upper_bound
            new_upper_bounded = other.upper_bounded
            new_upper_closed = other.upper_closed
        else:
            new_upper_bound = self.upper_bound
            new_upper_bounded = self.upper_bounded
            new_upper_closed = self.upper_closed
        return IntInterval(new_lower_bound, new_upper_bound, new_lower_closed, 
                               new_upper_closed, new_lower_bounded, new_upper_bounded)
    
    cpdef bool empty(IntInterval self):
        return ((self.lower_bounded and self.upper_bounded) and 
                ((((self.lower_bound == self.upper_bound) and 
                (not (self.lower_closed and self.upper_closed))) or
                self.lower_bound > self.upper_bound) or 
                 (self.lower_bound < self.upper_bound and 
                  (not (self.lower_closed or self.upper_closed)) and
                  self.adjacent(self.lower_bound, self.upper_bound))))
    
    cpdef bool richcmp(IntInterval self, IntInterval other, int op):
        cdef int lower_cmp
        cdef int upper_cmp
        if op == 0 or op == 1:
            lower_cmp = self.lower_cmp(other)
            if lower_cmp == -1:
                return True
            elif lower_cmp == 1:
                return False
            else: # lower_cmp == 0
                upper_cmp = self.upper_cmp(other)
                if upper_cmp == -1:
                    return True
                elif upper_cmp == 1:
                    return False
                else: # upper_cmp == 0
                    return op == 1
        elif op == 2:
            return (self.lower_cmp(other) == 0) and (self.upper_cmp(other) == 0)
        elif op == 3:
            return (self.lower_cmp(other) != 0) or (self.upper_cmp(other) != 0)
        elif op == 4 or op == 5:
            lower_cmp = self.lower_cmp(other)
            if lower_cmp == -1:
                return False
            elif lower_cmp == 1:
                return True
            else: # lower_cmp == 0
                upper_cmp = self.upper_cmp(other)
                if upper_cmp == -1:
                    return False
                elif upper_cmp == 1:
                    return True
                else: # upper_cmp == 0
                    return op == 5
    
    cpdef int lower_cmp(IntInterval self, IntInterval other):
        if not self.lower_bounded:
            if not other.lower_bounded:
                return 0
            else:
                return -1
        elif not other.lower_bounded:
            return 1
        if self.lower_bound < other.lower_bound:
            return -1
        elif self.lower_bound == other.lower_bound:
            if self.lower_closed and not other.lower_closed:
                return -1
            elif other.lower_closed and not self.lower_closed:
                return 1
            else:
                return 0
        else:
            return 1
    
    cpdef int upper_cmp(IntInterval self, IntInterval other):
        if not self.upper_bounded:
            if not other.upper_bounded:
                return 0
            else:
                return 1
        elif not other.upper_bounded:
            return -1
        if self.upper_bound < other.upper_bound:
            return -1
        elif self.upper_bound == other.upper_bound:
            if self.upper_closed and not other.upper_closed:
                return 1
            elif other.upper_closed and not self.upper_closed:
                return -1
            else:
                return 0
        else:
            return 1

# This is because static cpdef methods are not supported.  Otherwise this
# would be a static method of IntIntervalSet
cpdef tuple IntInterval_preprocess_intervals(tuple intervals):
    # Remove any empty intervals
    cdef IntInterval interval
    
    cdef list tmp = []
    for interval in intervals:
        if not interval.empty():
            tmp.append(interval)
    
    # If there are no nonempty intervals, return
    if not tmp:
        return tuple()
    
    # Sort
    tmp.sort()
    
    # Fuse any overlapping intervals
    cdef list tmp2 = []
    cdef IntInterval interval2
    cdef int overlap_cmp
    interval = tmp[0]
    for interval2 in tmp[1:]:
        overlap_cmp = interval.overlap_cmp(interval2)
        if (
            (overlap_cmp == 0) or 
            (overlap_cmp == -1 and interval.upper_bound == interval2.lower_bound and (interval.upper_closed or interval2.lower_closed)) or
            (overlap_cmp == 1 and interval2.upper_bound == interval.lower_bound and (interval2.upper_closed or interval.lower_closed))
            ):
            interval = interval.fusion(interval2)
        else:
            tmp2.append(interval)
            interval = interval2
    tmp2.append(interval)
    return tuple(tmp2)

cdef class IntIntervalSetIterator(BaseIntervalSetIterator):
    def __init__(IntIntervalSetIterator self, IntIntervalSet interval_set):
        self.index = 0
        self.interval_set = interval_set
    
    def __iter__(IntIntervalSetIterator self):
        return self
    
    def __next__(IntIntervalSetIterator self):
        self.index += 1
        if self.index <= self.interval_set.n_intervals:
            return self.interval_set.intervals[self.index-1]
        raise StopIteration

cdef class IntIntervalSet(BaseIntervalSet):
    def __init__(IntIntervalSet self, tuple intervals):
        '''
        The intervals must already be sorted and non-overlapping.
        '''
        self.intervals = intervals
        self.n_intervals = len(intervals)
    
    def __iter__(IntIntervalSet self):
        return IntIntervalSetIterator(self)
    
    def __getitem__(IntIntervalSet self, index):
        return self.intervals[index]
    
    cpdef bool lower_bounded(IntIntervalSet self):
        cdef IntInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[0]
            return interval.lower_bounded
        else:
            return True
    
    cpdef bool upper_bounded(IntIntervalSet self):
        cdef IntInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[self.n_intervals - 1]
            return interval.upper_bounded
        else:
            return True
    
    cpdef int lower_bound(IntIntervalSet self):
        cdef IntInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[0]
            return interval.lower_bound
        else:
            return 0
    
    cpdef int upper_bound(IntIntervalSet self):
        cdef IntInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[self.n_intervals - 1]
            return interval.upper_bound
        else:
            return 0
    
    cpdef tuple init_args(IntIntervalSet self):
        return (self.intervals,)
    
    cpdef bool contains(IntIntervalSet self, int item):
        '''
        Use binary search to determine whether item is in self.
        '''
        cdef int i, n
        cdef int low, high
        cdef int cmp
        cdef IntInterval interval 
        n = self.n_intervals
        low = 0
        high = n-1
        while high >= low:
            i = (high + low) / 2
            interval = self.intervals[i]
            cmp = interval.containment_cmp(item)
            if cmp == -1:
                high = i - 1
            elif cmp == 1:
                low = i + 1
            else: #if cmp == 0:
                return True
        return False

    cpdef bool subset(IntIntervalSet self, IntIntervalSet other):
        '''
        Return True if and only if self is a subset of other.
        '''
        cdef IntInterval self_interval, other_interval
        cdef int i, j, m, n
        cdef int overlap_cmp, cmp
        if self.empty():
            return True
        elif other.empty():
            return False
        m = self.n_intervals
        n = other.n_intervals
        j = 0
        other_interval = other.intervals[j]
        for i in range(m):
            self_interval = self.intervals[i]
            overlap_cmp = self_interval.overlap_cmp(other_interval)
            if overlap_cmp == -1:
                return False
            elif overlap_cmp == 0:
                if not self_interval.subset(other_interval):
                    return False
            elif overlap_cmp == 1:
                if j < n-1:
                    j += 1
                    other_interval = other.intervals[j]
                else:
                    return False
        return True
    
    cpdef bool equal(IntIntervalSet self, IntIntervalSet other):
        cdef IntInterval self_interval, other_interval
        cdef int i, n
        n = self.n_intervals
        if n != other.n_intervals:
            return False
        for i in range(n):
            self_interval = self.intervals[i]
            other_interval = other.intervals[i]
            if not self_interval.richcmp(other_interval, 2):
                return False
        return True
    
    cpdef bool richcmp(IntIntervalSet self, IntIntervalSet other, int op):
        if op == 0:
            return self.subset(other) and not self.equal(other)
        elif op == 1:
            return self.subset(other)
        elif op == 2:
            return self.equal(other)
        elif op == 3:
            return not self.equal(other)
        elif op == 4:
            return other.subset(self) and not other.equal(self)
        elif op == 5:
            return other.subset(self)
    
    cpdef bool empty(IntIntervalSet self):
        return self.n_intervals == 0 
    
    cpdef IntIntervalSet intersection(IntIntervalSet self, IntIntervalSet other):
        if self.empty() or other.empty():
            return self
        cdef int i, j, m, n, cmp, upper_cmp
        i = 0
        j = 0
        m = self.n_intervals
        n = other.n_intervals
        cdef IntInterval interval1, interval2
        interval1 = self.intervals[i]
        interval2 = other.intervals[j]
        cdef list new_intervals = []
        while True:
            cmp = interval1.overlap_cmp(interval2)
            if cmp == -1:
                i += 1
                if i <= m-1:
                    interval1 = self.intervals[i]
                else:
                    break
            elif cmp == 1:
                j += 1
                if j <= n-1:
                    interval2 = other.intervals[j]
                else:
                    break
            else:
                new_intervals.append(interval1.intersection(interval2))
                upper_cmp = interval1.upper_cmp(interval2)
                if upper_cmp <= 0:
                    i += 1
                    if i <= m-1:
                        interval1 = self.intervals[i]
                    else:
                        break
                if upper_cmp >= 0:
                    j += 1
                    if j <= n-1:
                        interval2 = other.intervals[j]
                    else:
                        break
        return IntIntervalSet(tuple(new_intervals))
    
    cpdef IntIntervalSet union(IntIntervalSet self, IntIntervalSet other):
        cdef IntInterval new_interval, interval1, interval2, next_interval
        if self.empty():
            return other
        if other.empty():
            return self
        interval1 = self.intervals[0]
        interval2 = other.intervals[0]
        
        cdef int i, j, m, n, cmp
        cdef bool richcmp, first = True
        i = 0
        j = 0
        m = self.n_intervals
        n = other.n_intervals
        cdef list new_intervals = []
        while i < m or j < n:
            if i == m:
                richcmp = False
            elif j == n:
                richcmp = True
            else:
                richcmp = interval1.richcmp(interval2, 1)
            if richcmp:
                next_interval = interval1 
                i += 1
                if i < m:
                    interval1 = self.intervals[i]
            else:
                next_interval = interval2
                j += 1
                if j < n:
                    interval2 = other.intervals[j]
            if first:
                first = False
                new_interval = next_interval
            else:
                cmp = new_interval.overlap_cmp(next_interval)
                if (cmp == 0 or 
                (cmp==-1 and new_interval.upper_bound == next_interval.lower_bound and 
                 (new_interval.upper_closed or next_interval.lower_closed)) or 
                 (cmp==1 and new_interval.lower_bound == next_interval.upper_bound and 
                 (new_interval.lower_closed or next_interval.upper_closed))):
                    new_interval = new_interval.fusion(next_interval)
                else:
                    new_intervals.append(new_interval)
                    new_interval = next_interval
        new_intervals.append(new_interval)
        return IntIntervalSet(tuple(new_intervals))
    
    cpdef IntIntervalSet complement(IntIntervalSet self):
        if self.empty():
            return IntIntervalSet((IntInterval(0, 0, True, True, False, False),))
        cdef IntInterval interval, previous
        cdef int i
        cdef n = self.n_intervals
        interval = self.intervals[0]
        cdef list new_intervals = []
        if interval.lower_bounded:
            new_intervals.append(IntInterval(0, interval.lower_bound, 
                                                 True, not interval.lower_closed, False, True))
        previous = interval
        for i in range(1,n):
            interval = self.intervals[i]
            new_intervals.append(IntInterval(previous.upper_bound, interval.lower_bound, not previous.upper_closed, 
                                                 not interval.lower_closed, True, True))
            previous = interval
        interval = self.intervals[n-1]
        if interval.upper_bounded:
            new_intervals.append(IntInterval(interval.upper_bound, 0, not interval.upper_closed, True, 
                                                 True, False))
        return IntIntervalSet(tuple(new_intervals))
            
    cpdef IntIntervalSet minus(IntIntervalSet self, IntIntervalSet other):
        return self.intersection(other.complement())

cdef class FloatInterval(BaseInterval):
    def __init__(BaseInterval self, double lower_bound, double upper_bound, bool lower_closed, 
                 bool upper_closed, bool lower_bounded, bool upper_bounded):
        self.lower_closed = lower_closed
        self.upper_closed = upper_closed
        self.lower_bounded = lower_bounded
        self.upper_bounded = upper_bounded
        if lower_bounded:
            self.lower_bound = lower_bound
        if upper_bounded:
            self.upper_bound = upper_bound
    
    # For some types, there is a concept of adjacent elements.  For example, 
    # there are no integers between 1 and 2 (although there are several real numbers).
    # If there is such a concept, it's possible for an interval to be empty even when 
    # the lower bound is strictly less than the upper bound, provided the bounds are strict 
    # (not closed).  The adjacent method is used to help determine such cases.
    cpdef bool adjacent(FloatInterval self, double lower, double upper):
        return False
    
    cpdef int containment_cmp(FloatInterval self, double item):
        if self.lower_bounded:
            if item < self.lower_bound:
                return -1
            elif item == self.lower_bound:
                if not self.lower_closed:
                    return -1
        # If we get here, the item satisfies the lower bound constraint
        if self.upper_bounded:
            if item > self.upper_bound:
                return 1
            elif item == self.upper_bound:
                if not self.upper_closed:
                    return 1
        # If we get here, the item also satisfies the upper bound constraint
        return 0
    
    cpdef bool contains(FloatInterval self, double item):
        return self.containment_cmp(item) == 0
    
    cpdef bool subset(FloatInterval self, FloatInterval other):
        '''
        Return True if and only if self is a subset of other.
        '''
        cdef int lower_cmp, upper_cmp
        lower_cmp = self.lower_cmp(other)
        upper_cmp = self.upper_cmp(other)
        return lower_cmp >= 0 and upper_cmp <= 0
        
    cpdef int overlap_cmp(FloatInterval self, FloatInterval other):
        '''
        Assume both are nonempty.  Return -1 if every element of self is less than every 
        element of other.  Return 0 if self and other intersect.  Return 1 if every element of 
        self is greater than every element of other.
        '''
        cdef int lower_cmp, upper_cmp
        lower_cmp = self.lower_cmp(other)
        upper_cmp = self.upper_cmp(other)
        
        if self.upper_bounded and other.lower_bounded:
            if self.upper_bound < other.lower_bound:
                return -1
            elif self.upper_bound == other.lower_bound:
                if self.upper_closed and other.lower_closed:
                    return 0
                else:
                    return -1
        if self.lower_bounded and other.upper_bounded:
            if self.lower_bound > other.upper_bound:
                return 1
            elif self.lower_bound == other.upper_bound:
                if self.lower_closed and other.upper_closed:
                    return 0
                else:
                    return 1
        return 0
    
    cpdef tuple init_args(FloatInterval self):
        return (self.lower_bound, self.upper_bound, self.lower_closed, self.upper_closed, 
                self.lower_bounded, self.upper_bounded)

    cpdef FloatInterval intersection(FloatInterval self, FloatInterval other):
        cdef int lower_cmp = self.lower_cmp(other)
        cdef int upper_cmp = self.upper_cmp(other)
        cdef double new_lower_bound, new_upper_bound
        cdef bool new_lower_closed, new_lower_bounded, new_upper_closed, new_upper_bounded
        if lower_cmp <= 0:
            new_lower_bound = other.lower_bound
            new_lower_bounded = other.lower_bounded
            new_lower_closed = other.lower_closed
        else:
            new_lower_bound = self.lower_bound
            new_lower_bounded = self.lower_bounded
            new_lower_closed = self.lower_closed
        
        if upper_cmp <= 0:
            new_upper_bound = self.upper_bound
            new_upper_bounded = self.upper_bounded
            new_upper_closed = self.upper_closed
        else:
            new_upper_bound = other.upper_bound
            new_upper_bounded = other.upper_bounded
            new_upper_closed = other.upper_closed
        return FloatInterval(new_lower_bound, new_upper_bound, new_lower_closed, 
                               new_upper_closed, new_lower_bounded, new_upper_bounded)
    
    cpdef FloatInterval fusion(FloatInterval self, FloatInterval other):
        '''
        Assume union of intervals is a single interval.  Return their union.  Results not correct
        if above assumption is violated.
        '''
        cdef int lower_cmp = self.lower_cmp(other)
        cdef int upper_cmp = self.upper_cmp(other)
        cdef double new_lower_bound, new_upper_bound
        cdef bool new_lower_closed, new_lower_bounded, new_upper_closed, new_upper_bounded
        if lower_cmp <= 0:
            new_lower_bound = self.lower_bound
            new_lower_bounded = self.lower_bounded
            new_lower_closed = self.lower_closed
        else:
            new_lower_bound = other.lower_bound
            new_lower_bounded = other.lower_bounded
            new_lower_closed = other.lower_closed
        
        if upper_cmp <= 0:
            new_upper_bound = other.upper_bound
            new_upper_bounded = other.upper_bounded
            new_upper_closed = other.upper_closed
        else:
            new_upper_bound = self.upper_bound
            new_upper_bounded = self.upper_bounded
            new_upper_closed = self.upper_closed
        return FloatInterval(new_lower_bound, new_upper_bound, new_lower_closed, 
                               new_upper_closed, new_lower_bounded, new_upper_bounded)
    
    cpdef bool empty(FloatInterval self):
        return ((self.lower_bounded and self.upper_bounded) and 
                ((((self.lower_bound == self.upper_bound) and 
                (not (self.lower_closed and self.upper_closed))) or
                self.lower_bound > self.upper_bound) or 
                 (self.lower_bound < self.upper_bound and 
                  (not (self.lower_closed or self.upper_closed)) and
                  self.adjacent(self.lower_bound, self.upper_bound))))
    
    cpdef bool richcmp(FloatInterval self, FloatInterval other, int op):
        cdef int lower_cmp
        cdef int upper_cmp
        if op == 0 or op == 1:
            lower_cmp = self.lower_cmp(other)
            if lower_cmp == -1:
                return True
            elif lower_cmp == 1:
                return False
            else: # lower_cmp == 0
                upper_cmp = self.upper_cmp(other)
                if upper_cmp == -1:
                    return True
                elif upper_cmp == 1:
                    return False
                else: # upper_cmp == 0
                    return op == 1
        elif op == 2:
            return (self.lower_cmp(other) == 0) and (self.upper_cmp(other) == 0)
        elif op == 3:
            return (self.lower_cmp(other) != 0) or (self.upper_cmp(other) != 0)
        elif op == 4 or op == 5:
            lower_cmp = self.lower_cmp(other)
            if lower_cmp == -1:
                return False
            elif lower_cmp == 1:
                return True
            else: # lower_cmp == 0
                upper_cmp = self.upper_cmp(other)
                if upper_cmp == -1:
                    return False
                elif upper_cmp == 1:
                    return True
                else: # upper_cmp == 0
                    return op == 5
    
    cpdef int lower_cmp(FloatInterval self, FloatInterval other):
        if not self.lower_bounded:
            if not other.lower_bounded:
                return 0
            else:
                return -1
        elif not other.lower_bounded:
            return 1
        if self.lower_bound < other.lower_bound:
            return -1
        elif self.lower_bound == other.lower_bound:
            if self.lower_closed and not other.lower_closed:
                return -1
            elif other.lower_closed and not self.lower_closed:
                return 1
            else:
                return 0
        else:
            return 1
    
    cpdef int upper_cmp(FloatInterval self, FloatInterval other):
        if not self.upper_bounded:
            if not other.upper_bounded:
                return 0
            else:
                return 1
        elif not other.upper_bounded:
            return -1
        if self.upper_bound < other.upper_bound:
            return -1
        elif self.upper_bound == other.upper_bound:
            if self.upper_closed and not other.upper_closed:
                return 1
            elif other.upper_closed and not self.upper_closed:
                return -1
            else:
                return 0
        else:
            return 1

# This is because static cpdef methods are not supported.  Otherwise this
# would be a static method of FloatIntervalSet
cpdef tuple FloatInterval_preprocess_intervals(tuple intervals):
    # Remove any empty intervals
    cdef FloatInterval interval
    
    cdef list tmp = []
    for interval in intervals:
        if not interval.empty():
            tmp.append(interval)
    
    # If there are no nonempty intervals, return
    if not tmp:
        return tuple()
    
    # Sort
    tmp.sort()
    
    # Fuse any overlapping intervals
    cdef list tmp2 = []
    cdef FloatInterval interval2
    cdef int overlap_cmp
    interval = tmp[0]
    for interval2 in tmp[1:]:
        overlap_cmp = interval.overlap_cmp(interval2)
        if (
            (overlap_cmp == 0) or 
            (overlap_cmp == -1 and interval.upper_bound == interval2.lower_bound and (interval.upper_closed or interval2.lower_closed)) or
            (overlap_cmp == 1 and interval2.upper_bound == interval.lower_bound and (interval2.upper_closed or interval.lower_closed))
            ):
            interval = interval.fusion(interval2)
        else:
            tmp2.append(interval)
            interval = interval2
    tmp2.append(interval)
    return tuple(tmp2)

cdef class FloatIntervalSetIterator(BaseIntervalSetIterator):
    def __init__(FloatIntervalSetIterator self, FloatIntervalSet interval_set):
        self.index = 0
        self.interval_set = interval_set
    
    def __iter__(FloatIntervalSetIterator self):
        return self
    
    def __next__(FloatIntervalSetIterator self):
        self.index += 1
        if self.index <= self.interval_set.n_intervals:
            return self.interval_set.intervals[self.index-1]
        raise StopIteration

cdef class FloatIntervalSet(BaseIntervalSet):
    def __init__(FloatIntervalSet self, tuple intervals):
        '''
        The intervals must already be sorted and non-overlapping.
        '''
        self.intervals = intervals
        self.n_intervals = len(intervals)
    
    def __iter__(FloatIntervalSet self):
        return FloatIntervalSetIterator(self)
    
    def __getitem__(FloatIntervalSet self, index):
        return self.intervals[index]
    
    cpdef bool lower_bounded(FloatIntervalSet self):
        cdef FloatInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[0]
            return interval.lower_bounded
        else:
            return True
    
    cpdef bool upper_bounded(FloatIntervalSet self):
        cdef FloatInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[self.n_intervals - 1]
            return interval.upper_bounded
        else:
            return True
    
    cpdef double lower_bound(FloatIntervalSet self):
        cdef FloatInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[0]
            return interval.lower_bound
        else:
            return 0.
    
    cpdef double upper_bound(FloatIntervalSet self):
        cdef FloatInterval interval
        if self.n_intervals > 0:
            interval = self.intervals[self.n_intervals - 1]
            return interval.upper_bound
        else:
            return 0.
    
    cpdef tuple init_args(FloatIntervalSet self):
        return (self.intervals,)
    
    cpdef bool contains(FloatIntervalSet self, double item):
        '''
        Use binary search to determine whether item is in self.
        '''
        cdef int i, n
        cdef int low, high
        cdef int cmp
        cdef FloatInterval interval 
        n = self.n_intervals
        low = 0
        high = n-1
        while high >= low:
            i = (high + low) / 2
            interval = self.intervals[i]
            cmp = interval.containment_cmp(item)
            if cmp == -1:
                high = i - 1
            elif cmp == 1:
                low = i + 1
            else: #if cmp == 0:
                return True
        return False

    cpdef bool subset(FloatIntervalSet self, FloatIntervalSet other):
        '''
        Return True if and only if self is a subset of other.
        '''
        cdef FloatInterval self_interval, other_interval
        cdef int i, j, m, n
        cdef int overlap_cmp, cmp
        if self.empty():
            return True
        elif other.empty():
            return False
        m = self.n_intervals
        n = other.n_intervals
        j = 0
        other_interval = other.intervals[j]
        for i in range(m):
            self_interval = self.intervals[i]
            overlap_cmp = self_interval.overlap_cmp(other_interval)
            if overlap_cmp == -1:
                return False
            elif overlap_cmp == 0:
                if not self_interval.subset(other_interval):
                    return False
            elif overlap_cmp == 1:
                if j < n-1:
                    j += 1
                    other_interval = other.intervals[j]
                else:
                    return False
        return True
    
    cpdef bool equal(FloatIntervalSet self, FloatIntervalSet other):
        cdef FloatInterval self_interval, other_interval
        cdef int i, n
        n = self.n_intervals
        if n != other.n_intervals:
            return False
        for i in range(n):
            self_interval = self.intervals[i]
            other_interval = other.intervals[i]
            if not self_interval.richcmp(other_interval, 2):
                return False
        return True
    
    cpdef bool richcmp(FloatIntervalSet self, FloatIntervalSet other, int op):
        if op == 0:
            return self.subset(other) and not self.equal(other)
        elif op == 1:
            return self.subset(other)
        elif op == 2:
            return self.equal(other)
        elif op == 3:
            return not self.equal(other)
        elif op == 4:
            return other.subset(self) and not other.equal(self)
        elif op == 5:
            return other.subset(self)
    
    cpdef bool empty(FloatIntervalSet self):
        return self.n_intervals == 0 
    
    cpdef FloatIntervalSet intersection(FloatIntervalSet self, FloatIntervalSet other):
        if self.empty() or other.empty():
            return self
        cdef int i, j, m, n, cmp, upper_cmp
        i = 0
        j = 0
        m = self.n_intervals
        n = other.n_intervals
        cdef FloatInterval interval1, interval2
        interval1 = self.intervals[i]
        interval2 = other.intervals[j]
        cdef list new_intervals = []
        while True:
            cmp = interval1.overlap_cmp(interval2)
            if cmp == -1:
                i += 1
                if i <= m-1:
                    interval1 = self.intervals[i]
                else:
                    break
            elif cmp == 1:
                j += 1
                if j <= n-1:
                    interval2 = other.intervals[j]
                else:
                    break
            else:
                new_intervals.append(interval1.intersection(interval2))
                upper_cmp = interval1.upper_cmp(interval2)
                if upper_cmp <= 0:
                    i += 1
                    if i <= m-1:
                        interval1 = self.intervals[i]
                    else:
                        break
                if upper_cmp >= 0:
                    j += 1
                    if j <= n-1:
                        interval2 = other.intervals[j]
                    else:
                        break
        return FloatIntervalSet(tuple(new_intervals))
    
    cpdef FloatIntervalSet union(FloatIntervalSet self, FloatIntervalSet other):
        cdef FloatInterval new_interval, interval1, interval2, next_interval
        if self.empty():
            return other
        if other.empty():
            return self
        interval1 = self.intervals[0]
        interval2 = other.intervals[0]
        
        cdef int i, j, m, n, cmp
        cdef bool richcmp, first = True
        i = 0
        j = 0
        m = self.n_intervals
        n = other.n_intervals
        cdef list new_intervals = []
        while i < m or j < n:
            if i == m:
                richcmp = False
            elif j == n:
                richcmp = True
            else:
                richcmp = interval1.richcmp(interval2, 1)
            if richcmp:
                next_interval = interval1 
                i += 1
                if i < m:
                    interval1 = self.intervals[i]
            else:
                next_interval = interval2
                j += 1
                if j < n:
                    interval2 = other.intervals[j]
            if first:
                first = False
                new_interval = next_interval
            else:
                cmp = new_interval.overlap_cmp(next_interval)
                if (cmp == 0 or 
                (cmp==-1 and new_interval.upper_bound == next_interval.lower_bound and 
                 (new_interval.upper_closed or next_interval.lower_closed)) or 
                 (cmp==1 and new_interval.lower_bound == next_interval.upper_bound and 
                 (new_interval.lower_closed or next_interval.upper_closed))):
                    new_interval = new_interval.fusion(next_interval)
                else:
                    new_intervals.append(new_interval)
                    new_interval = next_interval
        new_intervals.append(new_interval)
        return FloatIntervalSet(tuple(new_intervals))
    
    cpdef FloatIntervalSet complement(FloatIntervalSet self):
        if self.empty():
            return FloatIntervalSet((FloatInterval(0., 0., True, True, False, False),))
        cdef FloatInterval interval, previous
        cdef int i
        cdef n = self.n_intervals
        interval = self.intervals[0]
        cdef list new_intervals = []
        if interval.lower_bounded:
            new_intervals.append(FloatInterval(0., interval.lower_bound, 
                                                 True, not interval.lower_closed, False, True))
        previous = interval
        for i in range(1,n):
            interval = self.intervals[i]
            new_intervals.append(FloatInterval(previous.upper_bound, interval.lower_bound, not previous.upper_closed, 
                                                 not interval.lower_closed, True, True))
            previous = interval
        interval = self.intervals[n-1]
        if interval.upper_bounded:
            new_intervals.append(FloatInterval(interval.upper_bound, 0., not interval.upper_closed, True, 
                                                 True, False))
        return FloatIntervalSet(tuple(new_intervals))
            
    cpdef FloatIntervalSet minus(FloatIntervalSet self, FloatIntervalSet other):
        return self.intersection(other.complement())


# This is just a singleton
class unbounded:
    def __init__(self):
        raise NotImplementedError('unbounded should not be instantiated')

cdef dict interval_type_dispatch = {}
cdef dict interval_default_value_dispatch = {}
cdef dict interval_set_type_dispatch = {}
cdef dict interval_set_preprocessor_dispatch = {}
interval_default_value_dispatch[ObjectInterval] = None
interval_set_type_dispatch[ObjectInterval] = ObjectIntervalSet
interval_set_preprocessor_dispatch[ObjectInterval] = ObjectInterval_preprocess_intervals
interval_type_dispatch[date] = DateInterval
interval_default_value_dispatch[DateInterval] = None
interval_set_type_dispatch[DateInterval] = DateIntervalSet
interval_set_preprocessor_dispatch[DateInterval] = DateInterval_preprocess_intervals
interval_type_dispatch[int] = IntInterval
interval_default_value_dispatch[IntInterval] = 0
interval_set_type_dispatch[IntInterval] = IntIntervalSet
interval_set_preprocessor_dispatch[IntInterval] = IntInterval_preprocess_intervals
interval_type_dispatch[float] = FloatInterval
interval_default_value_dispatch[FloatInterval] = 0.
interval_set_type_dispatch[FloatInterval] = FloatIntervalSet
interval_set_preprocessor_dispatch[FloatInterval] = FloatInterval_preprocess_intervals
inverse_interval_type_dispatch = dict(map(tuple, map(reversed, interval_type_dispatch.items())))
def Interval(lower_bound=unbounded, upper_bound=unbounded, lower_closed=True, 
             upper_closed=True, interval_type=None):
    if interval_type is None:
        if lower_bound is not unbounded and type(lower_bound) in interval_type_dispatch:
            cls = interval_type_dispatch[type(lower_bound)]
        elif upper_bound is not unbounded and type(upper_bound) in interval_type_dispatch:
            cls = interval_type_dispatch[type(upper_bound)]
        else:
            cls = ObjectInterval
    elif interval_type in inverse_interval_type_dispatch:
        cls = interval_type
    elif interval_type in interval_type_dispatch:
        cls = interval_type_dispatch[interval_type]
    elif type(interval_type) in interval_type_dispatch:
        cls = interval_type_dispatch[type(interval_type)]
    else:
        cls = ObjectInterval
    default_value = interval_default_value_dispatch[cls]
    return cls(lower_bound if lower_bound is not unbounded else default_value,
               upper_bound if upper_bound is not unbounded else default_value,
               lower_closed, upper_closed, lower_bound is not unbounded, 
               upper_bound is not unbounded)

# Just a factory
def IntervalSet(*intervals, interval_type=None):
    if interval_type is None:
        if intervals:
            interval_cls = type(intervals[0])
            for interval in intervals[1:]:
                assert interval_cls is type(interval)
        else:
            interval_cls = ObjectInterval
    elif interval_type in inverse_interval_type_dispatch:
        interval_cls = interval_type
    elif interval_type in interval_type_dispatch:
        interval_cls = interval_type_dispatch[interval_type]
    elif type(interval_type) in interval_type_dispatch:
        interval_cls = interval_type_dispatch[type(interval_type)]
    else:
        interval_cls = ObjectInterval
    interval_set_type = interval_set_type_dispatch[interval_cls]
    interval_set_preprocessor = interval_set_preprocessor_dispatch[interval_cls]
    if intervals:
        processed_intervals = interval_set_preprocessor(intervals)
    else:
        processed_intervals = tuple()
    return interval_set_type(processed_intervals)


