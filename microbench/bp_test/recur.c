#include <stdio.h>

static int k=0;
void main() {
  void func (int, int);
  static int i = 1000;
  int j;
  for (j=0;j<1000;j++) {
    func(i,j);
  }
  //printf("k is %d\n",k);
}

void func(int l,int j) {
  k = j + l;
  if (l == 0) 
    return;
  else
    func(l-1, j);
}
