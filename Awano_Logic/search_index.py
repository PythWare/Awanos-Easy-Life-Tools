from array import array
from bisect import bisect_right

SEPARATOR = "\x00"
RESULT_LIMIT = 100000

class SearchIndex:
    def __init__(self):
        self.invalidate()

    def rebuild(self, entry_texts):
        texts = []
        entry_starts = array("q")
        for field_texts in entry_texts:
            entry_starts.append(len(texts))
            texts.extend(field_texts)
        entry_starts.append(len(texts))

        self.texts = texts
        self.entry_starts = entry_starts
        self.folded = None
        self.haystacks = {}
        self.stale = False

    def invalidate(self):
        self.texts = []
        self.entry_starts = array("q", [0])
        self.folded = None
        self.haystacks = {}
        self.stale = True

    def update(self, entry_index, field_index, text):
        if self.stale:
            return

        if entry_index + 1 >= len(self.entry_starts):
            self.invalidate()
            return

        record = self.entry_starts[entry_index] + field_index
        if record >= self.entry_starts[entry_index + 1]:
            self.invalidate()
            return

        if self.texts[record] == text:
            return

        self.texts[record] = text
        if self.folded is not None:
            self.folded[record] = text.lower()
        self.haystacks = {}

    def locate(self, record):
        entry_index = bisect_right(self.entry_starts, record) - 1
        return entry_index, record - self.entry_starts[entry_index]

    def text_at(self, record):
        return self.texts[record]

    def haystack(self, case_sensitive):
        cached = self.haystacks.get(case_sensitive)
        if cached is not None:
            return cached

        if case_sensitive:
            texts = self.texts
        else:
            if self.folded is None:
                self.folded = [text.lower() for text in self.texts]
            texts = self.folded

        haystack = SEPARATOR + SEPARATOR.join(texts) + SEPARATOR
        if haystack.count(SEPARATOR) != len(texts) + 1:
            haystack = SEPARATOR + SEPARATOR.join(
                text.replace(SEPARATOR, "") for text in texts
            ) + SEPARATOR

        self.haystacks[case_sensitive] = haystack
        return haystack

    def search(self, query, exact=False, case_sensitive=False, limit=RESULT_LIMIT):
        query = query.replace(SEPARATOR, "")
        matches = array("q")
        if self.stale or not query or not self.texts:
            return matches, False

        haystack = self.haystack(case_sensitive)
        needle = query if case_sensitive else query.lower()
        lead = 0
        if exact:
            needle = SEPARATOR + needle + SEPARATOR
            lead = 1

        find = haystack.find
        count = haystack.count
        separators_seen = 0
        scanned_to = 0
        position = find(needle)

        while position != -1:
            core = position + lead
            separators_seen += count(SEPARATOR, scanned_to, core)
            scanned_to = core
            matches.append(separators_seen - 1)
            if len(matches) >= limit:
                return matches, True

            record_end = find(SEPARATOR, core)
            if record_end == -1:
                break
            position = find(needle, record_end + 1 - lead)

        return matches, False
