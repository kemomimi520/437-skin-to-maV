import unittest

from PIL import Image

from converter.native_note_images import hold_body_canvas,hold_body_slice_edges


class NativeBodyGeometryTests(unittest.TestCase):
    def test_native_slice_caps_repeat_edges_without_resampling_original_content(self):
        source=Image.new('RGBA',(2,2))
        source.putdata([(20,100,50,255),(200,12,60,128),(100,10,20,0),(12,14,150,200)])
        result=hold_body_slice_edges(source)
        self.assertEqual(result.size,(2,4))
        self.assertEqual(result.crop((0,1,2,3)).tobytes(),source.tobytes())
        self.assertEqual(result.crop((0,0,2,1)).tobytes(),source.crop((0,0,2,1)).tobytes())
        self.assertEqual(result.crop((0,3,2,4)).tobytes(),source.crop((0,1,2,2)).tobytes())

    def test_two_pixel_body_is_not_rounded_from_ninety_to_one_hundred_units(self):
        image=hold_body_canvas(Image.new('RGBA',(2,2),'white'),width=90,lane_width=100,anchor_x=.5)
        box=image.getbbox()
        self.assertAlmostEqual((box[2]-box[0])/image.width*100,90,delta=.25)
        self.assertEqual(box[0]+box[2],image.width)

    def test_already_exact_texture_is_kept_at_original_density(self):
        original=Image.new('RGBA',(240,10),'white')
        image=hold_body_canvas(original,width=120,lane_width=135,anchor_x=.5)
        self.assertEqual(image.size,(270,10))
        self.assertEqual(image.crop((15,0,255,10)).tobytes(),original.tobytes())

    def test_horizontal_anchor_offset_is_encoded_only_when_it_fits_native_geometry(self):
        image=hold_body_canvas(Image.new('RGBA',(2,2),'white'),width=30,lane_width=100,anchor_x=0)
        box=image.getbbox()
        centre=((box[0]+box[2])/2/image.width-.5)*100
        self.assertAlmostEqual(centre,15,delta=.25)
        with self.assertRaisesRegex(ValueError,'固定轨道矩形'):
            hold_body_canvas(Image.new('RGBA',(2,2),'white'),width=90,lane_width=100,anchor_x=0)

    def test_incommensurate_stepmania_lane_width_does_not_explode_lcm(self):
        image=hold_body_canvas(Image.new('RGBA',(250,202),'white'),width=157.5,lane_width=332.96,anchor_x=.5)
        self.assertLessEqual(max(image.size),16384)
        box=image.getbbox()
        self.assertAlmostEqual((box[2]-box[0])/image.width*332.96,157.5,delta=.25)
        self.assertEqual(box[0]+box[2],image.width)


if __name__=='__main__':unittest.main()
