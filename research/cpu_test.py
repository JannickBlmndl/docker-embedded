"""Simple sleep task"""
import random
import time

def simple_calc():
    random_numbers = [random.random() for i in range(100000)]
    return sum(random_numbers)

def test_return():
    sometime = 3
    time.sleep(sometime)
    return sometime

if __name__=='__main__':
    test_return()
    