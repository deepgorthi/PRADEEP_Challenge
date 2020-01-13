from itertools import groupby
import re

pattern = re.compile(r'[456]\d{3}-(\d{4}-){2}\d{4}|[456]\d{15}')

def consecutive_num(num):
    return max(len(list(g)) for _, g in groupby(num))

n = int(input())
num_list = list(input() for _ in range(n))

for num in num_list:
    if not pattern.fullmatch(num) or consecutive_num(num.replace('-', '')) >= 4:
        print('Invalid')
    else:
        print('Valid')
