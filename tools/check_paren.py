path = r'C:\Users\PERKY\AndroidStudioProjects\untitled\untitled\lib\screens\inspector_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    s = f.read()
stack = []
for i,ch in enumerate(s):
    if ch == '(':
        stack.append(i)
    elif ch == ')':
        if stack:
            stack.pop()
        else:
            print('Unmatched ) at', i)
            break
if stack:
    last = stack[-1]
    line = s.count('\n', 0, last) + 1
    last_newline = s.rfind('\n', 0, last)
    if last_newline == -1:
        col = last + 1
    else:
        col = last - last_newline
    print('Unmatched ( at index', last, 'line', line, 'col', col)
else:
    print('All parens matched')
print('Done')
