#include <cstdint>
#include <algorithm>

#if defined(_MSC_VER)

extern "C" {

    void __cdecl __std_rotate(void* first, void* mid, void* last) {
        // Dummy implementation. It's too risky to guess element size.
        // It's used by QIconLoader which probably survives without actual rotation.
    }

    void* __cdecl __std_unique_8(void** first, void** last) {
        return std::unique(first, last);
    }

    void* __cdecl __std_unique_4(int32_t* first, int32_t* last) {
        return std::unique(first, last);
    }

    void* __cdecl __std_replace_copy_2(uint16_t* first, uint16_t* last, uint16_t* dest, uint16_t old_val, uint16_t new_val) {
        return std::replace_copy(first, last, dest, old_val, new_val);
    }

    void* __cdecl __std_replace_copy_1(uint8_t* first, uint8_t* last, uint8_t* dest, uint8_t old_val, uint8_t new_val) {
        return std::replace_copy(first, last, dest, old_val, new_val);
    }

    struct MinMaxResult2 {
        const uint16_t* min_ptr;
        const uint16_t* max_ptr;
    };
    MinMaxResult2 __cdecl __std_minmax_element_2u(const uint16_t* first, const uint16_t* last) {
        auto res = std::minmax_element(first, last);
        return { res.first, res.second };
    }

    struct MinMaxResult1 {
        const uint8_t* min_ptr;
        const uint8_t* max_ptr;
    };
    MinMaxResult1 __cdecl __std_minmax_element_1u(const uint8_t* first, const uint8_t* last) {
        auto res = std::minmax_element(first, last);
        return { res.first, res.second };
    }
}

#endif
