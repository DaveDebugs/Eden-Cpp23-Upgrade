#include <cstdint>
#include <utility>
#include <algorithm>

extern "C" {

void* __std_unique_8(uint64_t* first, uint64_t* last) {
    if (first == last) return last;
    uint64_t* result = first;
    while (++first != last) {
        if (*result != *first) {
            *(++result) = *first;
        }
    }
    return ++result;
}

void* __std_unique_4(uint32_t* first, uint32_t* last) {
    if (first == last) return last;
    uint32_t* result = first;
    while (++first != last) {
        if (*result != *first) {
            *(++result) = *first;
        }
    }
    return ++result;
}

void __std_replace_copy_1(const uint8_t* first, const uint8_t* last, uint8_t* result, uint8_t old_val, uint8_t new_val) {
    while (first != last) {
        *result++ = (*first == old_val) ? new_val : *first;
        first++;
    }
}

void __std_replace_copy_2(const uint16_t* first, const uint16_t* last, uint16_t* result, uint16_t old_val, uint16_t new_val) {
    while (first != last) {
        *result++ = (*first == old_val) ? new_val : *first;
        first++;
    }
}

struct Pair2u {
    const uint16_t* first;
    const uint16_t* second;
};

Pair2u __std_minmax_element_2u(const uint16_t* first, const uint16_t* last) {
    Pair2u result = { first, first };
    if (first == last) return result;
    const uint16_t* min_ptr = first;
    const uint16_t* max_ptr = first;
    while (++first != last) {
        if (*first < *min_ptr) min_ptr = first;
        if (*first >= *max_ptr) max_ptr = first;
    }
    result.first = min_ptr;
    result.second = max_ptr;
    return result;
}

void __std_rotate(uint8_t* first, uint8_t* mid, uint8_t* last) {
    if (first == mid || mid == last) return;
    
    uint8_t* p1 = first;
    uint8_t* p2 = mid - 1;
    while (p1 < p2) { uint8_t t = *p1; *p1++ = *p2; *p2-- = t; }
    
    p1 = mid;
    p2 = last - 1;
    while (p1 < p2) { uint8_t t = *p1; *p1++ = *p2; *p2-- = t; }
    
    p1 = first;
    p2 = last - 1;
    while (p1 < p2) { uint8_t t = *p1; *p1++ = *p2; *p2-- = t; }
}

}
